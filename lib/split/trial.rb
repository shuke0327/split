# frozen_string_literal: true
module Split
  class Trial
    attr_accessor :experiment
    attr_accessor :metadata

    def initialize(attrs = {})
      self.experiment   = attrs.delete(:experiment)
      self.alternative  = attrs.delete(:alternative)
      self.metadata  = attrs.delete(:metadata)

      @user             = attrs.delete(:user)
      @options          = attrs

      @alternative_choosen = false
    end

    def metadata
      @metadata ||= experiment.metadata[alternative.name] if experiment.metadata
    end

    def alternative
      @alternative ||=  if @experiment.has_winner?
                          @experiment.winner
                        end
    end

    def alternative=(alternative)
      @alternative = if alternative.kind_of?(Split::Alternative)
        alternative
      else
        @experiment.alternatives.find{|a| a.name == alternative }
      end
    end

    def complete!(goals=[], context = nil)
      if alternative
        if Array(goals).empty?
          alternative.increment_completion
        else
          Array(goals).each {|g| alternative.increment_completion(g) }
        end

        run_callback context, Split.configuration.on_trial_complete
      end
    end

    # Choose an alternative, add a participant, and save the alternative choice on the user. This
    # method is guaranteed to only run once, and will skip the alternative choosing process if run
    # a second time.
    def choose!(context = nil)
      @user.cleanup_old_experiments
      # Only run the process once
      return alternative if @alternative_choosen

      if override_is_alternative?
        self.alternative = @options[:override]
      elsif @options[:disabled] || Split.configuration.disabled?
        self.alternative = @experiment.control
      elsif @experiment.has_winner?
        self.alternative = @experiment.winner
      else
        cleanup_old_versions

        if exclude_user?
          self.alternative = @experiment.control
        elsif @user[@experiment.key]
          self.alternative = @user[@experiment.key]
        else
          self.alternative = @experiment.next_alternative

          # Increment the number of participants since we are actually choosing a new alternative
          self.alternative.increment_participation

          run_callback context, Split.configuration.on_trial_choose
        end
      end

      @user[@experiment.key] = alternative.name if should_store_alternative?
      @alternative_choosen = true
      run_callback context, Split.configuration.on_trial unless @options[:disabled] || Split.configuration.disabled?
      alternative
    end

    private

    def run_callback(context, callback_name)
      context.send(callback_name, self) if callback_name && context.respond_to?(callback_name, true)
    end

    def override_is_alternative?
      @experiment.alternatives.map(&:name).include?(@options[:override])
    end

    def should_store_alternative?
      if @options[:override] || @options[:disabled]
        Split.configuration.store_override
      else
        !exclude_user?
      end
    end

    def cleanup_old_versions
      if @experiment.version > 0
        keys = @user.keys.select { |k| k.match(Regexp.new(@experiment.name)) }
        keys_without_experiment(keys).each { |key| @user.delete(key) }
      end
    end

    def exclude_user?
      @options[:exclude] || @experiment.start_time.nil? || max_experiments_reached?
    end

    def max_experiments_reached?
      !Split.configuration.allow_multiple_experiments &&
          keys_without_experiment(@user.keys).length > 0
    end

    def keys_without_experiment(keys)
      keys.reject { |k| k.match(Regexp.new("^#{@experiment.key}(:finished)?$")) }
    end
  end
end
