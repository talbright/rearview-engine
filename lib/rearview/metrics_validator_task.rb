require 'json'

module Rearview
  class MetricsValidatorTask
    class StatsTaskError < StandardError; end;
    include Celluloid
    include Rearview::Logger
    attr_reader :cron_expression

    def initialize(cron_expression,start=true)
      @cron_expression = cron_expression
      schedule if start
    end

    def schedule
      logger.debug "#{self} schedule"
      delay = if cron_expression == '0 * * * * ?'
                60.0
              else
                Rearview::CronHelper.next_valid_time_after(cron_expression)
              end
      @timer = after(delay) { self.run }
    end

    def run
      logger.debug "#{self} run"
      validator = Rearview::MetricsValidator.new({ attributes: [:metrics], cache: true })
      Rearview::Job.schedulable.load.each do |job|
        validator.validate_each(job,:metrics,job.metrics)
        unless job.errors[:metrics].empty?
          alert_validation_failed(job)
        end
      end
    rescue
      logger.error "#{self} run failed: #{$!}\n#{$@.join("\n")}"
    ensure
      schedule
    end

    def alert_validation_failed(job)
      logger.debug "#{self} alerting on invalid metrics for #{job}"
      Rearview::MetricsValidationMailer.validation_failed_email(job.user.email,job).deliver
    end

  end
end
