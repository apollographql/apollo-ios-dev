#!/usr/bin/env ruby
# frozen_string_literal: true

output = `periphery scan --relative-results`
# This can be simplified in the future to `periphery scan --relative-results --format github-actions`
# https://github.com/peripheryapp/periphery/pull/746
title = 'Unused Code'
output
  .split("\n").select { |line| line.include?('.swift') }
  .map { |line| line.split(':', 5) }
  .map { |parts| "::warning file=#{parts[0]},line=#{parts[1]},col=#{parts[2]},title=#{title}::#{parts[4].strip}" }
  .each { |warning| puts warning }
