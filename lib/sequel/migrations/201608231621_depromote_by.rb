Sequel.migration do
  up do
    alter_table(:entity_events) do
      drop_column :by
    end
  end

  down do
  end
end
