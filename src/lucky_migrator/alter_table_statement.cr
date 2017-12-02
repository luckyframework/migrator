require "./*"

class LuckyMigrator::AlterTableStatement
  include LuckyMigrator::ColumnTypeOptionHelpers
  include LuckyMigrator::ColumnDefaultHelpers

  alias ColumnType = String.class | Time.class | Int32.class | Int64.class | Bool.class | Float.class
  alias ColumnDefaultType = String | Time | Int32 | Int64 | Float32 | Float64 | Bool | Symbol

  getter statement = IO::Memory.new
  getter rows = [] of String
  getter dropped_rows = [] of String

  def initialize(@table_name : Symbol)
  end

  def build
    with self yield
    self
  end

  def statements
    [alter_statement]
  end

  def alter_statement
    String.build do |statement|
      statement << "ALTER TABLE #{@table_name}"
      statement << "\n"
      statement << (rows + dropped_rows).join(",\n")
    end
  end

  macro add(type_declaration, default = nil, **type_options)
    {% options = type_options.empty? ? nil : type_options %}

    {% if type_declaration.type.is_a?(Union) %}
      add_column :{{ type_declaration.var }}, {{ type_declaration.type.types.first }}, optional: true, default: {{ default }}, options: {{ options }}
    {% else %}
      add_column :{{ type_declaration.var }}, {{ type_declaration.type }}, default: {{ default }}, options: {{ options }}
    {% end %}
  end

  def add_column(name : Symbol, type : (Bool | String | Time | Int32 | Int64 | Float).class, optional = false, default : ColumnDefaultType? = nil, options : NamedTuple? = nil)

    if options
      column_type_with_options = column_type(type, **options)
    else
      column_type_with_options = column_type(type)
    end

    rows << String.build do |row|
      row << "  ADD "
      row << name.to_s
      row << " "
      row << column_type_with_options
      row << null_fragment(optional)
      row << default_value(type, default) unless default.nil?
    end
  end

  def remove(name : Symbol)
    dropped_rows << "  DROP #{name.to_s}"
  end

  def null_fragment(optional)
    if optional
      ""
    else
      " NOT NULL"
    end
  end
end
