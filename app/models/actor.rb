# frozen_string_literal: true

class Actor < ApplicationRecord
  self.primary_key = :id
  has_one_attached :avatar
end
