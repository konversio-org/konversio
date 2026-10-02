# frozen_string_literal: true

require 'ipaddr'
require 'resolv'
require 'uri'

# Decides whether a URL may be shown to end customers as a knowledge-source
# citation. The check is deliberately network-level: a self-hosted Pilot can
# be pointed at arbitrary operator URLs, so a link is only eligible when its
# host resolves and *every* resolved address is publicly routable. The check
# runs at citation-resolution time (not only when the document is saved)
# because DNS answers and document state change.
#
# IPv4, IPv4-mapped IPv6, and the common IPv6 translation/documentation
# prefixes are treated as non-public. Any parse/resolution failure yields no
# URL. The building blocks (IPAddr + Resolv) mirror the app's SSRF filtering.
module Pilot::CitationUrlValidator
  module_function

  # Non-public IPv4 ranges: this-host, RFC1918, CGNAT, loopback, link-local,
  # documentation/benchmark ranges, multicast, and reserved space.
  DENIED_IPV4 = [
    IPAddr.new('0.0.0.0/8'),
    IPAddr.new('10.0.0.0/8'),
    IPAddr.new('100.64.0.0/10'),
    IPAddr.new('127.0.0.0/8'),
    IPAddr.new('169.254.0.0/16'),
    IPAddr.new('172.16.0.0/12'),
    IPAddr.new('192.0.0.0/24'),
    IPAddr.new('192.0.2.0/24'),
    IPAddr.new('192.88.99.0/24'),
    IPAddr.new('192.168.0.0/16'),
    IPAddr.new('198.18.0.0/15'),
    IPAddr.new('198.51.100.0/24'),
    IPAddr.new('203.0.113.0/24'),
    IPAddr.new('224.0.0.0/4'),
    IPAddr.new('240.0.0.0/4'),
    IPAddr.new('255.255.255.255/32')
  ].freeze

  # Non-public IPv6 ranges plus translation/documentation prefixes that can
  # map back to local address space (IPv4-mapped, NAT64, 6to4, Teredo).
  DENIED_IPV6 = [
    IPAddr.new('::/128'),
    IPAddr.new('::1/128'),
    IPAddr.new('fc00::/7'),
    IPAddr.new('fe80::/10'),
    IPAddr.new('ff00::/8'),
    IPAddr.new('2001::/32'),
    IPAddr.new('2001:db8::/32'),
    IPAddr.new('2002::/16'),
    IPAddr.new('64:ff9b::/96')
  ].freeze

  # Returns `url` when it is customer-visible, otherwise nil.
  def eligible_url(url)
    uri = parse_http_uri(url)
    return nil if uri.nil?
    return nil if uri.path.to_s.downcase.end_with?('.pdf')
    return nil unless host_resolves_publicly?(uri.host)

    url.to_s
  end

  def parse_http_uri(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return nil if uri.host.blank?
    return nil if uri.userinfo.present?

    uri
  rescue URI::InvalidURIError
    nil
  end

  def host_resolves_publicly?(host)
    addresses = Resolv.getaddresses(host.to_s)
    return false if addresses.empty?

    addresses.all? { |address| publicly_routable?(address) }
  rescue StandardError
    false
  end

  def publicly_routable?(address)
    ip = IPAddr.new(address.to_s)
    return publicly_routable?(ip.native.to_s) if ipv4_in_ipv6?(ip)

    denied = ip.ipv4? ? DENIED_IPV4 : DENIED_IPV6
    denied.none? { |range| range.include?(ip) }
  rescue IPAddr::Error
    false
  end

  def ipv4_in_ipv6?(ip)
    return false if ip.ipv4?

    ip.ipv4_mapped? || ip.ipv4_compat?
  end
end
