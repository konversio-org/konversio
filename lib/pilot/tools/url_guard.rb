# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'uri'

# Resolves a hostname once and rejects URLs whose resolved address falls into
# any of the documented private / loopback / link-local / metadata ranges.
#
# Performing the resolution here (and feeding the resolved IP directly to the
# HTTP client) is what mitigates DNS rebinding: the address checked is the
# address connected.
module Pilot::Tools::UrlGuard
  module_function

  DENIED_CIDRS = [
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('169.254.0.0/16'),
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('::1/128'),
    IPAddr.new('fc00::/7'),
    IPAddr.new('fe80::/10')
  ].freeze

  Result = Struct.new(:host, :ip, :denied_range, keyword_init: true) do
    def denied?
      !denied_range.nil?
    end
  end

  # Resolves `host` once and returns a Result with the chosen IP plus
  # the matching denied CIDR (if any). Returns a denied Result with
  # `ip = nil` if resolution fails.
  def resolve(host)
    addresses = Resolv.getaddresses(host.to_s)
    ip = addresses.find { |a| valid_ip?(a) }
    return Result.new(host: host, ip: nil, denied_range: :unresolved) if ip.nil?

    parsed_ip = IPAddr.new(ip)
    denied = DENIED_CIDRS.find { |range| range.include?(parsed_ip) }
    Result.new(host: host, ip: ip, denied_range: denied)
  end

  # True if the resolved address for `host` is in any denied CIDR.
  def denied?(host)
    resolve(host).denied?
  end

  def valid_ip?(value)
    IPAddr.new(value.to_s)
    true
  rescue IPAddr::Error
    false
  end
end
