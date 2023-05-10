# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0

module OpenTelemetry
  module SDK
    module Trace
      module Samplers
        # @api private
        #
        # Implements consistent sampling based on a probability.
        class ConsistentProbabilityBased
          include ConsistentProbabilityTraceState

          attr_reader :description


          def initialize(probability)
            @probability = probability

            if probability < 2e-62
              @p_floor = 63
              @p_ceil = @p_ceil_probability = 0
              @description = 'ConsistentProbabilityBased{0}'
              return
            end

            # the floor is
            @p_floor = (Math.frexp(probability)[1] - 1).abs
            @p_ceil = @p_floor + 1
            floor = Math.ldexp(1.0, -@p_floor)
            ceil = Math.ldexp(1.0, -@p_ceil)
            @p_ceil_probability = (probability - floor) / (ceil - floor)
            @description = format('ConsistentProbabilityBased{%.6f}', probability)
          end

          def probability_values
            ret = {}
            if @probability < 2e-62
              ret[:p_that_keeps_less_spans] = 63
              ret[:p_that_keeps_more_spans] = 0
              ret[:prob_of_using_p_that_keeps_less_spans] = 0
            else
              ret[:p_that_keeps_less_spans] = (Math.frexp(@probability)[1] - 1).abs
              # a lower absolute value of p will sample in more spans
              ret[:p_that_keeps_more_spans] = ret[:p_that_keeps_less_spans] - 1

              # TODO: can I make these calculations 2**-p instead of ldexp?
              lightly_sampling_p_float = Math.ldexp(1.0, -ret[:p_that_keeps_less_spans])
              heavily_sampling_p_float = Math.ldexp(1.0, -ret[:p_that_keeps_more_spans])

              ret[:prob_of_using_p_that_keeps_less_spans] = (heavily_sampling_p_float - @probability) / (heavily_sampling_p_float - lightly_sampling_p_float)
            end

            ret
          end

          def ==(other)
            @description == other.description
          end

          # @api private
          #
          # See {Samplers}.
          def should_sample?(trace_id:, parent_context:, links:, name:, kind:, attributes:)
            parent_span_context = OpenTelemetry::Trace.current_span(parent_context).context
            p = probabilistic_p
            if parent_span_context.valid?
              tracestate = parent_span_context.tracestate
              parse_ot_vendor_tag(tracestate) do |_, in_r, rest|
                r = if in_r.nil? || in_r > 62
                      OpenTelemetry.logger.debug("ConsistentProbabilitySampler: potentially inconsistent trace detected - r: #{in_r.inspect}")
                      generate_r(trace_id)
                    else
                      in_r
                    end
                if p <= r
                  Result.new(decision: Decision::RECORD_AND_SAMPLE, tracestate: update_tracestate(tracestate, p, r, rest))
                else
                  Result.new(decision: Decision::DROP, tracestate: update_tracestate(tracestate, nil, r, rest))
                end
              end
            else
              r = generate_r(trace_id)
              if p <= r
                Result.new(decision: Decision::RECORD_AND_SAMPLE, tracestate: new_tracestate(p: p, r: r))
              else
                Result.new(decision: Decision::DROP, tracestate: new_tracestate(r: r))
              end
            end
          end

          private

          def probabilistic_p
            if Random.rand < @p_ceil_probability
              @p_ceil
            else
              @p_floor
            end
          end
        end
      end
    end
  end
end
