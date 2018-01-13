#!/usr/bin/env ruby

require_relative "./common"

enclient = ENClient.new

require 'optparse'

Invocation = Struct.new(
  :inbox,
  :agenda
)

def parse_invocation
  invocation = Invocation.new

  OptionParser.new do |p|
    p.on("-inbox") do
      invocation.inbox = true
    end

    p.on("-agenda") do
      enclient.agenda = true
    end
  end.parse(ARGV)

  invocation
end

inv = parse_invocation

if inv.inbox
  enclient.inbox
elsif inv.agenda
  enclient.agenda
end
