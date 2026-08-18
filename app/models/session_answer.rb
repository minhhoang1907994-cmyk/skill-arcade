class SessionAnswer < ApplicationRecord
  belongs_to :game_session
  belongs_to :question
  has_many :ai_gradings, dependent: :destroy

  validates :position, numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :game_session_id }
  validates :answer, presence: true
  validates :score, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :answered_at, presence: true
end
