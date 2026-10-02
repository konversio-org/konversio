class Api::V1::Accounts::Articles::BulkActionsController < Api::V1::Accounts::BaseController
  before_action :portal
  before_action :check_authorization
  before_action :set_articles, only: [:update_status, :update_category, :delete_articles]

  def translate
    return unless validate_translate_params?

    duplicates = existing_translations
    if duplicates.any? && !force_translate?
      return render json: { duplicate_articles: duplicates.map { |article| { id: article.id, title: article.title } } },
                    status: :conflict
    end

    @articles.find_each do |article|
      Pilot::Articles::TranslateJob.perform_later(Current.account, article.id, @locale, @category&.id, Current.user)
    end

    head :ok
  end

  def update_status
    return render_could_not_create_error(I18n.t('portals.articles.no_articles_found')) if @articles.none?
    return render_could_not_create_error(I18n.t('portals.articles.invalid_status')) unless Article.statuses.key?(params[:status])

    ActiveRecord::Base.transaction do
      @articles.find_each { |article| article.update!(status: params[:status]) }
    end
    head :ok
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.message)
  end

  def update_category
    return render_could_not_create_error(I18n.t('portals.articles.no_articles_found')) if @articles.none?
    return render_could_not_create_error(I18n.t('portals.articles.category_not_found')) unless category_valid?

    ActiveRecord::Base.transaction do
      @articles.find_each { |article| article.update!(category_id: params[:category_id]) }
    end
    head :ok
  rescue ActiveRecord::RecordInvalid => e
    render_could_not_create_error(e.message)
  end

  def delete_articles
    return render_could_not_create_error(I18n.t('portals.articles.no_articles_found')) if @articles.none?

    @articles.destroy_all
    head :ok
  end

  private

  def portal
    @portal ||= Current.account.portals.find_by!(slug: params[:portal_id])
  end

  def check_authorization
    authorize(Article, :create?)
  end

  def set_articles
    @articles = @portal.articles.where(id: params[:ids])
  end

  def category_valid?
    @portal.categories.exists?(id: params[:category_id])
  end

  # Translation is the only bulk action with its own params; keep them separate
  # from the status/category/delete flow so those paths stay untouched.
  def translate_params
    params.permit(:locale, :category_id, :force, ids: [])
  end

  def force_translate?
    ActiveModel::Type::Boolean.new.cast(translate_params[:force])
  end

  def validate_translate_params?
    @locale = translate_params[:locale]
    @category = @portal.categories.find_by(id: translate_params[:category_id], locale: @locale)
    @articles = @portal.articles.where(id: translate_params[:ids])

    pilot_translation_available? && translation_locale_valid? && translation_category_valid? && translation_articles_valid?
  end

  def pilot_translation_available?
    return true if Current.account.feature_enabled?('pilot_tasks')

    render_could_not_create_error(I18n.t('portals.articles.translation_unavailable'))
    false
  end

  def translation_locale_valid?
    return true if @portal.allowed_locale_codes.include?(@locale)

    render_could_not_create_error(I18n.t('portals.articles.locale_not_available'))
    false
  end

  def translation_category_valid?
    return true if translate_params[:category_id].blank?
    return true if @category.present?

    render_could_not_create_error(I18n.t('portals.articles.category_not_found'))
    false
  end

  def translation_articles_valid?
    return true if @articles.any?

    render_could_not_create_error(I18n.t('portals.articles.no_articles_found'))
    false
  end

  # Existing translations share the selected articles' root article and the
  # requested locale, so they're the ones an overwrite would replace.
  def existing_translations
    root_ids = @articles.map { |article| Article.find_root_article_id(article) }
    @portal.articles.where(associated_article_id: root_ids, locale: @locale)
  end
end
