require 'set'
module Neo4j
  # This is here to support the removed functionality of being able to
  # defined indexes and constraints on models
  # This code should be removed later
  module ModelSchema
    MODEL_INDEXES = {}
    MODEL_CONSTRAINTS = {}
    REQUIRED_INDEXES = {}

    class << self
      def add_defined_constraint(model, property_name)
        MODEL_CONSTRAINTS[model] ||= Set.new
        MODEL_CONSTRAINTS[model] << property_name.to_sym
      end

      def add_defined_index(model, property_name)
        MODEL_INDEXES[model] ||= Set.new
        MODEL_INDEXES[model] << property_name.to_sym
      end

      def add_required_index(model, property_name)
        REQUIRED_INDEXES[model] ||= Set.new
        REQUIRED_INDEXES[model] << property_name.to_sym
      end

      def defined_constraint?(model, property_name)
        MODEL_CONSTRAINTS[model] &&
          MODEL_CONSTRAINTS[model].include?(property_name.to_sym)
      end

      def model_constraints
        constraints = Neo4j::ActiveBase.current_session.constraints.each_with_object({}) do |row, result|
          result[row[:label]] ||= []
          result[row[:label]] << row[:properties]
        end

        schema_elements_list(MODEL_CONSTRAINTS, constraints)
      end

      def model_indexes
        indexes = Neo4j::ActiveBase.current_session.indexes.each_with_object({}) do |row, result|
          result[row[:label]] ||= []
          result[row[:label]] << row[:properties]
        end

        schema_elements_list(MODEL_INDEXES, indexes) +
          schema_elements_list(REQUIRED_INDEXES, indexes).reject(&:last)
        # reject required indexes which are already in the DB
      end

      # should be private
      def schema_elements_list(by_model, db_results)
        by_model.flat_map do |model, property_names|
          label = model.mapped_label_name.to_sym
          property_names.map do |property_name|
            exists = db_results[label] && db_results[label].include?([property_name])
            [model, label, property_name, exists]
          end
        end
      end

      def validate_model_schema!
        messages = {index: [], constraint: []}
        [[:constraint, model_constraints], [:index, model_indexes]].each do |type, schema_elements|
          schema_elements.map do |model, label, property_name, exists|
            if exists
              log_warning!(type, model, property_name)
            else
              messages[type] << force_add_message(type, label, property_name)
            end
          end
        end

        return if messages.values.all?(&:empty?)

        fail validation_error_message(messages)
      end

      def validation_error_message(messages)
        <<MSG
          Some schema elements were defined by the model (which is no longer support), but they do not exist in the database.  Run the following to create them:

#{messages[:constraint].join("\n")}
#{messages[:index].join("\n")}

(zshell users may need to escape the brackets)
MSG
      end

      def force_add_message(index_or_constraint, label, property_name)
        "rake neo4j:generate_schema_migration[#{index_or_constraint},#{label},#{property_name}]"
      end

      def log_warning!(index_or_constraint, model, property_name)
        Neo4j::ActiveBase.logger.warn "WARNING: The #{index_or_constraint} option is no longer supported (Defined on #{model.name} for #{property_name})"
      end
    end
  end
end
