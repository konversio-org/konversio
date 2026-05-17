module Custom
  module Pilot
    module Tools
      # Fetch a single contact by id, scoped to the running account. Returns
      # a short summary block (name, email, phone, contact-type, salient
      # custom attributes). Used when the agent asks "who is contact 17?" or
      # the model wants to enrich a conversation reply with contact context.
      class GetContact < Base
        description 'Fetch a single contact in the current account by id. ' \
                    'Returns name, email, phone, identifier, contact type, and custom attributes.'
        param :id, type: 'integer', desc: 'Contact id (account-scoped)', required: true

        def name
          'get_contact'
        end


        def perform(tool_context, id:)
          account = account_for(tool_context)
          return 'Account context unavailable; cannot fetch contact.' if account.blank?

          contact = account.contacts.find_by(id: id)
          return "Contact #{id} not found in this account." if contact.blank?

          format_contact(contact)
        rescue StandardError => e
          Rails.logger.warn("[pilot.tools.get_contact] #{e.class}: #{e.message}")
          "Tool error while fetching contact: #{e.message}"
        end

        private

        def format_contact(contact)
          attrs = {
            id: contact.id,
            name: contact.name,
            email: contact.email,
            phone: contact.phone_number,
            identifier: contact.identifier,
            contact_type: contact.contact_type,
            custom_attributes: contact.custom_attributes,
            additional_attributes: contact.additional_attributes
          }
          attrs.compact.map { |k, v| "#{k}: #{v}" }.join("\n")
        end
      end
    end
  end
end
