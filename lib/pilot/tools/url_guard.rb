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
#
# Operators can carve out specific endpoints via PILOT_TOOL_ALLOWED_HOSTS
# (comma-separated `host` or `host:port`). This is an explicit allowlist — safe
# in production — not a blanket "allow private networks" switch: only the named
# hosts bypass the guard; everything else (including the cloud metadata IP at
# 169.254.169.254) stays blocked.
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

  # Resolves `host` once and returns a Result with the chosen IP plus the
  # matching denied CIDR (if any). Returns a denied Result with `ip = nil` if
  # resolution fails. An allowlisted host/port clears the denied range.
  def resolve(host, port = nil)
    addresses = Resolv.getaddresses(host.to_s)
    ip = addresses.find { |a| valid_ip?(a) }
    return Result.new(host: host, ip: nil, denied_range: :unresolved) if ip.nil?

    parsed_ip = IPAddr.new(ip)
    denied = allowlisted?(host, port) ? nil : DENIED_CIDRS.find { |range| range.include?(parsed_ip) }
    Result.new(host: host, ip: ip, denied_range: denied)
  end

  # True if the resolved address for `host` is in any denied CIDR.
  def denied?(host, port = nil)
    resolve(host, port).denied?
  end

  # True when `host` (and `port`, when the matching entry pins one) is named in
  # PILOT_TOOL_ALLOWED_HOSTS. Matching is exact and case-insensitive; an entry
  # without a port matches any port.
  def allowlisted?(host, port = nil)
    normalized = normalize_host(host)
    return false if normalized.empty?

    allowed_endpoints.any? do |entry_host, entry_port|
      entry_host == normalized && (entry_port.nil? || entry_port == port&.to_s)
    end
  end

  def allowed_endpoints
    ENV.fetch('PILOT_TOOL_ALLOWED_HOSTS', '').split(',').filter_map do |raw|
      entry = raw.strip
      next if entry.empty?

      split_host_port(entry)
    end
  end

  # Splits an allowlist entry into [host, port]. Brackets are honored only for a
  # properly paired IPv6 literal (`[::1]` or `[::1]:8200`); every other use of a
  # bracket is kept verbatim, so a malformed entry (e.g. `[127.0.0.1]`) can only
  # ever match literally — it never collapses to a bare IP and widens the list.
  def split_host_port(entry)
    match = entry.match(/\A(\[[0-9a-f:]+\]|[^\[\]:]+):(\d+)\z/i)
    return [normalize_host(entry), nil] unless match

    [normalize_host(match[1]), match[2]]
  end

  # Canonicalises a host: trims, downcases, and unwraps the brackets of a paired
  # IPv6 literal (`[::1]` -> `::1`). Non-IPv6 content or mismatched brackets are
  # left intact so they can only ever match literally.
  def normalize_host(host)
    canonical = host.to_s.strip.downcase
    match = canonical.match(/\A\[([0-9a-f:]+)\]\z/)
    match ? match[1] : canonical
  end

  def valid_ip?(value)
    IPAddr.new(value.to_s)
    true
  rescue IPAddr::Error
    false
  end
end
