Sequel.migration do
  up do
    alter_table(:entity_events) do
      add_column :by, :char, size: 24, null: true
      add_column :at, :timestamp, null: true
    end
  end

  down do
  end
end
