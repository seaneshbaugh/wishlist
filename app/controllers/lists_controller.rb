class ListsController < ApplicationController
  before_action :authenticate_user!

  def index
    @lists = visible_lists.ordered.load
    @visible_item_counts = ListItem.visible_to(current_user)
      .where(list_id: @lists.map(&:id))
      .group(:list_id)
      .count
  end

  def show
    @list = find_list

    load_list_items

    @list_item = @list.list_items.build
  end

  def new
    @list = current_user.lists.build
  end

  def create
    @list = current_user.lists.build(list_params)

    created = current_user.with_lock do
      @list.save
    end

    if created
      flash[:success] = t(".success")

      redirect_to list_url(@list), status: :see_other
    else
      flash.now[:error] = t(".error")

      render "new", status: :unprocessable_entity
    end
  end

  def edit
    @list = find_list
  end

  def update
    @list = find_list

    if @list.update(list_params)
      flash[:success] = t(".success")

      redirect_to edit_list_url(@list), status: :see_other
    else
      flash.now[:error] = t(".error")

      render "edit", status: :unprocessable_entity
    end
  end

  def destroy
    @list = find_list

    if @list.destroy
      flash[:success] = t(".success")

      redirect_to lists_url, status: :see_other
    else
      load_list_items

      @list_item = @list.list_items.build

      flash.now[:error] = t(".error")

      render "show", status: :unprocessable_entity
    end
  end

  def reorder
    positions = reorder_positions

    reordered = current_user.with_lock do
      next false unless valid_reorder_positions?(positions)

      lists_by_id = current_user.lists.where(id: positions.map { |position| position[:id] }).index_by(&:id)

      positions.each do |position|
        lists_by_id.fetch(position[:id]).update!(position: position[:position])
      end
    end

    if reordered
      head :no_content
    else
      render json: { error: t(".invalid_list_positions") }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: t(".error"), details: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def owner
    @owner ||= begin
      if params[:friend_id]
        current_user.friends.friendly.find(params[:friend_id])
      else
        current_user
      end
    end
  end
  helper_method :owner

  private

  def visible_lists
    if owner == current_user
      owner.lists
    else
      owner.lists.publicly_visible
    end
  end

  def find_list
    visible_lists.friendly.find(params[:id])
  end

  def load_list_items
    @list_items = @list.list_items.visible_to(current_user).ordered.includes(:purchases)

    @list_items_by_priority = @list_items.group_by(&:priority)
  end

  def list_params
    params.require(:list).permit(:name, :description, :public)
  end

  def reorder_positions
    positions = params.permit(positions: [ :id, :position ])[:positions]

    return unless positions.is_a?(Array)

    positions.map do |position|
      return unless position.is_a?(ActionController::Parameters)

      { id: Integer(position[:id].to_s, 10), position: Integer(position[:position].to_s, 10) }
    end
  rescue ArgumentError
    nil
  end

  def valid_reorder_positions?(positions)
    return false unless positions.present?

    ids = positions.map { |position| position[:id] }
    positions_values = positions.map { |position| position[:position] }

    ids.uniq.length == ids.length &&
      ids.sort == current_user.lists.ids.sort &&
      positions_values.sort == (0...ids.length).to_a
  end
end
