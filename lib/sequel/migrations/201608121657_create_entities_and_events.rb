Sequel.migration do
  up do
    create_table? :entities do
      column :id, :char, primary_key: true, size: 24
      String :_type
      integer :snapshot_key
      integer :version
      column :snapshot, :jsonb
    end

    create_table? :entity_events do
      column :id, :char, primary_key: true, size: 24
      String :_type
      column :_entity_id, :char, size: 24
      integer :entity_version
      column :data, :jsonb
    end
  end

  down do
    drop_table(:entities)
    drop_table(:entity_events)
  end
end
