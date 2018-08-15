require "colorize"
require "./*"

abstract class LuckyMigrator::Migration::V1
  include LuckyMigrator::StatementHelpers

  macro inherited
    LuckyMigrator::Runner.migrations << self

    def version
      get_version_from_filename
    end

    macro get_version_from_filename
      {{@type.name.split("::").last.gsub(/V/, "")}}
    end
  end

  abstract def migrate
  abstract def version
  abstract def public

  getter prepared_statements = [] of String

  def initialize(schema : String = "")
    if public || schema.empty?
      @schema = "public"
    else
      @schema = schema
    end
  end

  # Unless already migrated, calls migrate which in turn calls statement
  # helpers to generate and collect SQL statements in the
  # @prepared_statements array. Each statement is then executed in  a
  # transaction and tracked upon completion.
  def up(quiet = false)
    if migrated?
      puts "Already migrated #{self.class.name.colorize(:cyan)}"
    else
      reset_prepared_statements
      migrate
      execute_in_transaction @prepared_statements do |tx|
        track_migration(tx)
        unless quiet
          puts "Migrated #{self.class.name.colorize(:green)}"
        end
      end
    end
  end

  # Same as #up except calls rollback method in migration.
  def down(quiet = false)
    if pending?
      puts "Already rolled back #{self.class.name.colorize(:cyan)}"
    else
      reset_prepared_statements
      rollback
      execute_in_transaction @prepared_statements do |tx|
        untrack_migration(tx)
        unless quiet
          puts "Rolled back #{self.class.name.colorize(:green)}"
        end
      end
    end
  end

  def pending?
    !migrated?
  end

  def migrated?
    DB.open(LuckyRecord::Repo.settings.url) do |db|
      db.query_one? "SELECT id FROM public.migrations WHERE version = $1 AND schema = $2", version, @schema, as: Int32
    end
  end

  private def track_migration(tx : DB::Transaction)
    tx.connection.exec "INSERT INTO public.migrations(version,schema) VALUES ($1,$2)", version, @schema
  end

  private def untrack_migration(tx : DB::Transaction)
    tx.connection.exec "DELETE FROM public.migrations WHERE version = $1 AND schema = $2", version, @schema
  end

  private def execute(statement : String)
    @prepared_statements << statement
  end

  # Accepts an array of SQL statements and a block. Iterates through the
  # array, running each statement in a transaction then yields the block
  # with the transaction as an argument.
  #
  # # Usage
  #
  # ```
  # execute_in_transaction ["DROP TABLE comments;"] do |tx|
  #   tx.connection.exec "DROP TABLE users;"
  # end
  # ```
  private def execute_in_transaction(statements : Array(String))
    DB.open(LuckyRecord::Repo.settings.url) do |db|
      db.transaction do |tx|
        tx.connection.exec set_schema unless public
        statements.each do |s|
          tx.connection.exec s
        end
        yield tx
      end
    end
  end

  def reset_prepared_statements
    @prepared_statements = [] of String
  end

  def set_schema
    <<-SQL
    SET search_path TO #{@schema};
    SQL
  end
end
