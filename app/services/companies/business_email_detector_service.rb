class Companies::BusinessEmailDetectorService
  # RFC 2606 / 6761 reserved domains and TLDs: never real businesses, so they
  # must not trigger company creation (also keeps test fixtures from polluting
  # the companies table).
  RESERVED_DOMAINS = %w[example.com example.net example.org example.edu].freeze
  RESERVED_TLDS = %w[test example invalid localhost].freeze

  def initialize(email)
    @email = email
  end

  def perform
    return false if @email.blank?

    domain = @email.to_s.split('@').last.to_s.downcase
    return false if reserved_domain?(domain)

    address = ValidEmail2::Address.new(@email)
    return false unless address.valid?
    return false if address.disposable_domain?

    EmailProviderInfo.call(@email).blank?
  end

  private

  def reserved_domain?(domain)
    RESERVED_DOMAINS.include?(domain) || RESERVED_TLDS.include?(domain.split('.').last)
  end
end
