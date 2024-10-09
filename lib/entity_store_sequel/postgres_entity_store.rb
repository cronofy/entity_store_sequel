require 'bson'
require 'entity_store'
require 'json'
require 'pigeon_hole'
require 'sequel'
require 'uri'

module EntityStoreSequel
  class PostgresEntityStore
    include EntityStore::Logging

    Sequel.extension :migration

    class << self
      attr_accessor :connection_string
      attr_writer :connect_timeout
      attr_accessor :native_json_hash

      def database
        return @_database if @_database

        self.database = Sequel.connect(connection_string)
      end

      def database=(db)
        @_database = db

        if db.adapter_scheme == :postgres
          @_database.extension :pg_json
          self.native_json_hash = true
        else
          self.native_json_hash = false
        end

        @_database
      end

      def init
        migration_path = File.expand_path("../../sequel/migrations", __FILE__)
        Sequel::Migrator.run(self.database, migration_path, table: :entity_store_schema_migration)
      end
    end

    def initialize(database_connection = nil)
      return unless database_connection

      @database_connection = database_connection
      @database_connection.extension :pg_json
    end

    def open
      @database_connection || PostgresEntityStore.database
    end

    def entities
      @entities_collection ||= open[:entities]
    end

    def events
      @events_collection ||= open[:entity_events]
    end

    def clear
      open.drop_table(:entities, :entity_events)
      @entities_collection = nil
      @events_collection = nil
    end

    def ensure_indexes
    end

    def clear_entity_events(id, excluded_types)
      if excluded_types.empty?
        events.where(_entity_id: id).delete
      else
        events.where(_entity_id: id).select(:id, :_type).each do |event|
          next if excluded_types.include?(event[:_type])
          events.where(id: event[:id]).delete
        end
      end
    end

    def add_entity(entity, id = BSON::ObjectId.new)
      entities.insert(:id => id.to_s, :_type => entity.class.name, :version => entity.version)
      id.to_s
    end

    def save_entity(entity)
      entities.where(:id => entity.id).update(:version => entity.version)
    end

    # Public: create a snapshot of the entity and store in the entities collection
    #
    def snapshot_entity(entity)
      if entity.class.respond_to? :entity_store_snapshot_key
        # If there is a snapshot key, store it too
        snapshot_key = entity.class.entity_store_snapshot_key
      else
        # Otherwise, make sure there isn't one set
        snapshot_key = nil
      end

      unless entities[:id => entity.id]
        entities.insert(:id => entity.id, :_type => entity.class.name, :version => entity.version)
      end

      entities
        .where(:id => entity.id)
        .update(:snapshot => PigeonHole.generate(entity.attributes), :snapshot_key => snapshot_key )
    end

    # Public - remove the snapshot for an entity
    #
    def remove_entity_snapshot(id)
      entities.where(:id => id).update(:snapshot => nil)
    end

    # Public: remove all snapshots
    #
    # type        - String optional class name for the entity
    #
    def remove_snapshots(type=nil)
      if type
        entities.where(:_type => type).update(:snapshot => nil)
      else
        entities.update(:snapshot => nil)
      end
    end

    def add_events(items)
      events_with_id = items.map { |e| [ BSON::ObjectId.new, e ] }
      add_events_with_ids(events_with_id)
    end

    def upsert_events(items)
      events_with_id = items.map do |e|
        [ e._id, e ]
      end

      filtered_events = []
      events_with_id.each do |id, event|
        next if events.where(id: id.to_s).count > 0

        filtered_events << event

        doc = event_doc(id, event)
        events.insert(doc)
      end

      filtered_events
    end

    def add_events_with_ids(event_id_map)
      event_id_map.each do |id, event|
        doc = event_doc(id, event)
        events.insert(doc)
      end
    end

    def event_doc(id, event)
      {
        :id => id.to_s,
        :_type => event.class.name,
        :_entity_id => event.entity_id.to_s,
        :entity_version => event.entity_version,
        :at => event.attributes[:at],
        :data => PigeonHole.generate(hash_without_keys(event.attributes, :entity_id, :at, :entity_version, :_id)),
      }
    end

    # Public: loads the entity from the store, including any available snapshots
    # then loads the events to complete the state
    #
    # ids           - Array of Strings representation of BSON::ObjectId
    # options       - Hash of options (default: {})
    #                 :raise_exception - Boolean (default: true)
    #
    # Returns an array of entities
    def get_entities(ids, options={})
      ids.each do |id|
        begin
          BSON::ObjectId.from_string(id)
        rescue BSON::ObjectId::Invalid
          raise NotFound.new(id) if options.fetch(:raise_exception, true)
          nil
        end
      end

      entities.where(:id => ids).map do |attrs|
        begin
          entity_type = EntityStore::Config.load_type(attrs[:_type])

          # Check if there is a snapshot key in use
          if entity_type.respond_to? :entity_store_snapshot_key
            active_key = entity_type.entity_store_snapshot_key

            # Discard the snapshot if the keys don't match
            unless active_key == attrs[:snapshot_key]
              attrs.delete(:snapshot)
            end
          end

          if attrs[:snapshot]
            if self.class.native_json_hash
              hash = attrs[:snapshot].to_h
            else
              hash = PigeonHole.parse(attrs[:snapshot])
            end

            entity = entity_type.new(hash)
          else
            entity = entity_type.new({'id' => attrs[:id].to_s })
          end
        rescue => e
          log_error "Error loading type - type=#{attrs[:_type]} id=#{attrs[:id]}", e
          raise
        end

        entity
      end

    end

    # Public:  get events for an array of criteria objects
    #           because each entity could have a different reference
    #           version this allows optional criteria to be specifed
    #
    #
    # criteria  - Hash :id mandatory, :since_version optional
    #
    # Examples
    #
    # get_events_for_criteria([ { id: "23232323"}, { id: "2398429834", since_version: 4 } ] )
    #
    # Returns Hash with id as key and Array of Event instances as value
    def get_events(criteria)
      return {} if criteria.empty?

      query = events

      criteria.each_with_index do |item, i|
        filter_method = filter_method_name(i)
        if item[:since_version]
          query = query.send(filter_method, Sequel.lit('_entity_id = ? AND entity_version > ?', item[:id], item[:since_version]))
        else
          query = query.send(filter_method, Sequel.lit('_entity_id = ?', item[:id]))
        end
      end

      result = query.to_hash_groups(:_entity_id)

      result.each do |id, events|
        events.sort_by! { |attrs| [attrs[:entity_version], attrs[:id].to_s] }

        # Convert the attributes into event objects
        events.map! do |attrs|
          begin
            if self.class.native_json_hash
              hash = attrs[:data].to_h
            else
              hash = PigeonHole.parse(attrs[:data])
            end

            hash[:_id] = attrs[:id]
            hash[:entity_version] = attrs[:entity_version]
            hash[:entity_id] = attrs[:_entity_id]
            hash[:at] = attrs[:at]
            EntityStore::Config.load_type(attrs[:_type]).new(hash)
          rescue => e
            log_error "Error loading type - type=#{attrs[:_type]} id=#{attrs[:id]} entity_id=#{attrs[:entity_id]}", e
            nil
          end
        end

        events.compact!
      end

      criteria.each do |item|
        result[item[:id].to_s] ||= []
      end

      result
    end

    private

    def get_raw_events(entity_id)
      rows = events.where(:_entity_id => entity_id).order_by(:entity_version, :id)
      rows.map do |attrs|
        if self.class.native_json_hash
          hash = attrs[:data].to_h
        else
          hash = PigeonHole.parse(attrs[:data])
        end

        hash[:_id] = attrs[:id]
        hash[:_type] = attrs[:_type]
        hash[:entity_version] = attrs[:entity_version]
        hash[:entity_id] = attrs[:_entity_id]
        hash[:at] = attrs[:at]

        hash
      end
    end

    def filter_method_name(index)
      index == 0 ? :where : :or
    end

    def hash_without_keys(hash, *keys)
      hash_dup = hash.dup
      keys.each { |key| hash_dup.delete(key) }
      hash_dup
    end
  end
end
