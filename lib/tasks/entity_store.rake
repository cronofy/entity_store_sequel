require "#{Rake.application.original_dir}/lib/entity_store"

namespace :entity_store_sequel do
  task :drop_db do
    EntityStore::PostgresEntityStore.new.clear
  end

  task :create_db do
    EntityStore::PostgresEntityStore.init
  end
end
