# frozen_string_literal: true

require_relative 'base'

module Desiru
  module Jobs
    class OptimizerJob < Base
      sidekiq_options queue: 'low', retry: 1

      def perform(job_id, optimizer_class_name, program_class_name, trainset, optimizer_options = {})
        optimizer_class = Object.const_get(optimizer_class_name)
        program_class = Object.const_get(program_class_name)
        optimizer = optimizer_class.new(**optimizer_options)
        program = program_class.new

        # Store initial status
        update_status(job_id, 'running', progress: 0, message: 'Starting optimization')

        # Compile the program with progress tracking
        optimized_program = optimizer.compile(program, trainset: trainset) do |progress|
          update_status(job_id, 'running', progress: progress, message: "Optimizing... #{progress}% complete")
        end

        # Store the optimized program configuration
        store_result(job_id, {
                       success: true,
                       optimized_config: optimized_program.to_config,
                       metrics: optimizer.final_metrics,
                       completed_at: Time.now.iso8601
                     }, ttl: 86_400) # 24 hours TTL

        update_status(job_id, 'completed', progress: 100, message: 'Optimization completed successfully')
      rescue StandardError => e
        store_result(job_id, {
                       success: false,
                       error: e.message,
                       error_class: e.class.name,
                       completed_at: Time.now.iso8601
                     })
        update_status(job_id, 'failed', message: "Optimization failed: #{e.message}")
        raise
      end
    end
  end
end
