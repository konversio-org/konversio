## Capability: onboarding-channel-detection

Brand enrichment from the signup domain — website scrape for title, colors, logo, and social profiles plus MX-record mailbox-provider inference — with non-destructive pre-fill of the account-details form and detected-channel suggestions during inbox setup. Reference implementation (MIT, verbatim port is legal): upstream `app/services/website_branding_service.rb`, `app/services/social_link_parser.rb`, `app/jobs/account/branding_enrichment_job.rb`, `app/javascript/dashboard/routes/dashboard/onboarding/account-details/useAccountEnrichment.js`, and `app/javascript/dashboard/routes/dashboard/onboarding/inbox-setup/{useDetectedChannels,channelMatchers,constants}.js`.

---

## ADDED Requirements

### Requirement: asynchronous brand enrichment after signup

When an account is created through signup, the system SHALL enqueue a low-priority background job that fetches the signup email domain's homepage through the SSRF-safe fetch layer, extracts brand data (page title, theme color, favicon, outbound social profile links), and stores the result as `brand_info` in `account.custom_attributes` only when none exists yet.

#### Scenario: enrichment stores brand_info

- Given a new account created with email `admin@acme.com` and no `brand_info`
- When the enrichment job completes successfully
- Then `account.custom_attributes['brand_info']` contains the domain, page title, colors, logos, and social links extracted from `https://acme.com`
- And the account name is set from the page title when one was found

#### Scenario: existing brand_info is never overwritten

- Given an account whose `brand_info` was already populated
- When the enrichment job completes
- Then the existing `brand_info` is left unchanged

#### Scenario: fetch failure is silent

- Given the domain homepage cannot be fetched or parsed
- When the enrichment job runs
- Then no `brand_info` is stored
- And no exception is raised to the job backend

### Requirement: enrichment step lifecycle

While enrichment is pending, the account's step cursor SHALL be `enrichment`; when the job finishes it SHALL advance the cursor to `account_details` (only if it still reads `enrichment`) and broadcast an `account.enrichment_completed` websocket event to an account administrator.

#### Scenario: cursor advances and event is broadcast

- Given an account whose cursor is `enrichment`
- When the enrichment job finishes (successfully or not)
- Then the cursor becomes `account_details`
- And an `account.enrichment_completed` event is broadcast carrying the account id

#### Scenario: late job does not regress a manually advanced cursor

- Given the cursor has already advanced past `enrichment`
- When the enrichment job finishes
- Then the cursor is left unchanged

### Requirement: mailbox provider inference from MX records

The system SHALL resolve the signup domain's MX records and infer the mailbox provider as `google` or `microsoft` by matching MX hostnames against the providers' known mail domains on a registrable-domain (label) boundary; any other result SHALL be nil. DNS failures SHALL be treated as "provider unknown", never as errors.

#### Scenario: Google-hosted domain

- Given `acme.com` has MX records under `google.com`
- When enrichment runs for `admin@acme.com`
- Then `brand_info.email_provider` is `google`

#### Scenario: lookalike domains are not misclassified

- Given `acme.com` has an MX record pointing at `notgoogle.com`
- When enrichment runs
- Then `brand_info.email_provider` is nil

#### Scenario: DNS resolution fails

- Given the MX lookup times out or errors
- When enrichment runs
- Then `brand_info.email_provider` is nil
- And the rest of the brand data is still stored

### Requirement: non-destructive account-details pre-fill

The account-details form SHALL pre-fill empty fields from enriched data and environment hints — website from the submitted website or brand domain, industry from the first detected industry, locale best-matched from the browser language against enabled locales (exact, then base language, then account locale), timezone from the browser — and MUST never overwrite a value the user has already typed. While the cursor is `enrichment` the form SHALL indicate that enrichment is in progress, and SHALL stop waiting after 30 seconds, populating from whatever data is then available.

#### Scenario: late-arriving enrichment fills only untouched fields

- Given the user has typed a company size but left industry empty
- When enrichment data arrives
- Then the industry field is populated from the enriched data
- And the typed company size is unchanged

#### Scenario: enrichment timeout

- Given the cursor remains `enrichment` for more than 30 seconds
- When the timeout elapses
- Then the form stops showing the enriching state
- And fields are populated from currently available data

#### Scenario: user edits are reported at submit

- Given fields were auto-populated from enrichment
- When the user submits the form
- Then the client can identify which enrichable fields (website, company size, industry) the user actually edited, comparing against the snapshot taken before any value normalization

### Requirement: detected channels in inbox setup

The inbox-setup step SHALL derive suggested channel rows from `brand_info.socials` and the detected email provider, MUST hide channels whose installation OAuth credentials are missing or whose feature flag is off, and SHALL fall back to a bounded default suggestion list (at most 3) so the step is never empty. A detected channel row is marked connected when a real inbox matches on `channel_type` — and additionally on `provider` for email channels, since Google and Microsoft share `Channel::Email`.

#### Scenario: social profiles become channel rows

- Given `brand_info.socials` contains a Facebook page URL and a WhatsApp link
- When the inbox-setup step renders
- Then rows for Facebook and WhatsApp are displayed with the handle extracted from each URL
- And the WhatsApp handle is rendered as `+<digits>` and other platforms as `@handle` per platform convention

#### Scenario: detected email provider is shown but deferred

- Given `brand_info.email_provider` is `google`
- When the inbox-setup step renders
- Then the detected email channel does not appear as a connectable row
- And Gmail remains available in the full channel catalog as a set-up-later entry

#### Scenario: unconfigured channels are hidden

- Given Facebook was detected but the installation has no Facebook app credentials configured
- When the inbox-setup step renders
- Then the Facebook row is not displayed

#### Scenario: default suggestions when nothing is detected

- Given no `brand_info` socials and no detected email provider
- When the inbox-setup step renders
- Then up to 3 default channel suggestions are shown, filtered to configured and enabled channels

#### Scenario: connected state matches the real inbox

- Given a Gmail inbox exists (`channel_type` `Channel::Email`, `provider` `google`)
- When a detected Google email row is evaluated
- Then it is treated as connected
- And an Outlook inbox in the same account does not mark the Google row connected
