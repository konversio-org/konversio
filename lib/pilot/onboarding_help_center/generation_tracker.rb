class Pilot::OnboardingHelpCenter::GenerationTracker
  STATUS_FIELD = 'status'.freeze
  TOTAL_FIELD = 'total'.freeze
  FINISHED_FIELD = 'finished'.freeze
  REASON_FIELD = 'reason'.freeze

  GENERATING = 'generating'.freeze
  COMPLETED = 'completed'.freeze
  SKIPPED = 'skipped'.freeze
  TERMINAL_STATES = [COMPLETED, SKIPPED].freeze

  def initialize(generation_id)
    @generation_id = generation_id
  end

  def begin!
    Redis::Alfred.hset(key, STATUS_FIELD, GENERATING)
    Redis::Alfred.hset(key, FINISHED_FIELD, 0)
    Redis::Alfred.expire(key, Pilot::OnboardingHelpCenter::GENERATION_TTL)
  end

  def state
    Redis::Alfred.hget(key, STATUS_FIELD).presence
  end

  def terminal?
    TERMINAL_STATES.include?(state)
  end

  def total
    Redis::Alfred.hget(key, TOTAL_FIELD).to_i
  end

  def finished
    Redis::Alfred.hget(key, FINISHED_FIELD).to_i
  end

  def total=(count)
    Redis::Alfred.hset(key, TOTAL_FIELD, count.to_i)
    Redis::Alfred.expire(key, Pilot::OnboardingHelpCenter::GENERATION_TTL)
  end

  def finish_article!
    return if state.blank? || terminal?

    finished = Redis::Alfred.with { |conn| conn.hincrby(key, FINISHED_FIELD, 1) }
    complete! if finished.to_i >= total
  end

  def complete!
    Redis::Alfred.hset(key, STATUS_FIELD, COMPLETED)
    Redis::Alfred.expire(key, Pilot::OnboardingHelpCenter::GENERATION_TTL)
  end

  def skip!(reason)
    return if terminal?

    Redis::Alfred.hset(key, STATUS_FIELD, SKIPPED)
    Redis::Alfred.hset(key, REASON_FIELD, reason.to_s)
    Redis::Alfred.expire(key, Pilot::OnboardingHelpCenter::GENERATION_TTL)
  end

  private

  def key
    @key ||= format(Redis::Alfred::PILOT_ONBOARDING_HELP_CENTER, generation_id: @generation_id)
  end
end
