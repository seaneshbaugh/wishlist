module ApplicationHelper
  def maximum_length(record, attribute)
    record
      .class
      .validators_on(attribute)
      .grep(ActiveModel::Validations::LengthValidator)
      .first
      &.options
      &.fetch(:maximum)
  end

  def minimum_length(record, attribute)
    record
      .class
      .validators_on(attribute)
      .grep(ActiveModel::Validations::LengthValidator)
      .first
      &.options
      &.fetch(:minimum)
  end
end
