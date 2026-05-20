# frozen_string_literal: true

class Api::V2::Accounts::Pilot::LogbookEntriesController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :set_contact, only: [:index, :create]
  before_action :set_entry, only: [:update, :destroy]

  def index
    @entries = @contact.pilot_logbook_entries.latest
    render json: @entries.map { |entry| serialize_entry(entry) }
  end

  def create
    @entry = @contact.pilot_logbook_entries.create!(logbook_entry_params)
    render json: serialize_entry(@entry), status: :created
  end

  def update
    @entry.update!(logbook_entry_params)
    render json: serialize_entry(@entry)
  end

  def destroy
    @entry.destroy!
    head :ok
  end

  private

  def ensure_feature_enabled
    return if Current.account.pilot_enabled && Current.account.pilot_logbook_enabled

    render json: { error: 'Pilot Logbook is not enabled for this account' }, status: :forbidden
  end

  def set_contact
    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def set_entry
    @entry = Current.account.pilot_logbook_entries.find(params[:id])
  end

  def logbook_entry_params
    params.require(:logbook_entry).permit(:content, metadata: {})
  end

  def serialize_entry(entry)
    {
      id: entry.id,
      content: entry.content,
      metadata: entry.metadata,
      created_at: entry.created_at,
      updated_at: entry.updated_at
    }
  end
end
