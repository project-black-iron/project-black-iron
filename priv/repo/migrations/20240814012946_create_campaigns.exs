defmodule BlackIron.Repo.Migrations.CreateCampaigns do
  use Ecto.Migration

  def change do
    create table(:campaigns) do
      add :pid, :string, null: false
      add :name, :citext, null: false
      add :description, :text, null: false

      add :_rev, :string, null: false
      add :_revisions, {:array, :string}, default: [], null: false
      add :deleted_at, :naive_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:campaigns, [:pid])

    create table(:campaign_memberships) do
      add :user_id, references(:users, column: :pid, type: :string, on_delete: :delete_all),
        null: false

      add :campaign_id, references(:campaigns, on_delete: :delete_all), null: false
      add :roles, {:array, :string}, default: ["player"], null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:campaign_memberships, [:user_id, :campaign_id])
  end
end
