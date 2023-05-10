# frozen_string_literal: true

# Copyright The OpenTelemetry Authors
#
# SPDX-License-Identifier: Apache-2.0
# Based on https://github.com/open-telemetry/opentelemetry-go-contrib/blob/main/samplers/probability/consistent/base2_test.go

require 'test_helper'

describe OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased do
  let(:sample_rate) { 0.5 }
  subject { OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(sample_rate) }

  describe '#probability_values' do
    describe 'for non-powers of two' do
      it "returns correct values" do
        # 0.1
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.1).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(4)
        _(result[:p_that_keeps_more_spans]).must_equal(3)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(0.4)

        # 0.05
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.05).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(5)
        _(result[:p_that_keeps_more_spans]).must_equal(4)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(0.4)

        # 0.003
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.003).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(9)
        _(result[:p_that_keeps_more_spans]).must_equal(8)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(3)).must_equal(0.464)

        # 0.75
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.75).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(1)
        _(result[:p_that_keeps_more_spans]).must_equal(0)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(0.5)

        # 0.6
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.6).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(1)
        _(result[:p_that_keeps_more_spans]).must_equal(0)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(0.8)

        # 0.9
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.9).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(1)
        _(result[:p_that_keeps_more_spans]).must_equal(0)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(0.2)
      end
    end

    describe 'powers of two' do
      it 'returns correct probabilities' do
        # 1
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(1).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(0)
        _(result[:p_that_keeps_more_spans]).must_equal(-1)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(1.0)

        # 0.5
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.5).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(1)
        _(result[:p_that_keeps_more_spans]).must_equal(0)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(1)

        # 0.25
        result = OpenTelemetry::SDK::Trace::Samplers::ConsistentProbabilityBased.new(0.25).probability_values
        _(result[:p_that_keeps_less_spans]).must_equal(2)
        _(result[:p_that_keeps_more_spans]).must_equal(1)
        _(result[:prob_of_using_p_that_keeps_less_spans].round(1)).must_equal(1)
      end
    end
  end

  describe '#description' do
    it 'returns a description' do
      _(subject.description).must_equal('ConsistentProbabilityBased{0.500000}')
    end
  end

  describe '#should_sample?' do
    it 'populates tracestate for a sampled root span' do
      result = call_sampler(subject, trace_id: trace_id(1), parent_context: OpenTelemetry::Context::ROOT)
      _(result.tracestate['ot']).must_equal('p:1;r:62')
      _(result).must_be :sampled?
    end

    it 'populates tracestate for an unsampled root span' do
      result = call_sampler(subject, trace_id: trace_id(-1), parent_context: OpenTelemetry::Context::ROOT)
      _(result.tracestate['ot']).must_equal('r:0')
      _(result).wont_be :sampled?
    end

    it 'populates tracestate with the parent r for a sampled child span' do
      tid = trace_id(1)
      ctx = parent_context(trace_id: tid, ot: 'p:1;r:1')
      result = call_sampler(subject, trace_id: tid, parent_context: ctx)
      _(result.tracestate['ot']).must_equal('p:1;r:1')
      _(result).must_be :sampled?
    end

    it 'populates tracestate without p for an unsampled child span' do
      tid = trace_id(-1)
      ctx = parent_context(trace_id: tid, ot: 'p:0;r:0')
      result = call_sampler(subject, trace_id: tid, parent_context: ctx)
      _(result.tracestate['ot']).must_equal('r:0')
      _(result).wont_be :sampled?
    end

    it 'generates a new r if r is missing in the parent tracestate' do
      tid = trace_id(1)
      ctx = parent_context(trace_id: tid, ot: 'p:1')
      result = call_sampler(subject, trace_id: tid, parent_context: ctx)
      _(result.tracestate['ot']).must_equal('p:1;r:62')
      _(result).must_be :sampled?
    end

    it 'generates a new r if r is invalid in the parent tracestate' do
      tid = trace_id(1)
      ctx = parent_context(trace_id: tid, ot: 'p:1;r:63')
      result = call_sampler(subject, trace_id: tid, parent_context: ctx)
      _(result.tracestate['ot']).must_equal('p:1;r:62')
      _(result).must_be :sampled?
    end

    # TODO: statistical tests
  end
end
