class PurchasesController < ApplicationController
  def create
    @list_item = find_list_item

    @list = @list_item.list

    @purchase = @list_item.purchases.build(purchase_params)

    @purchase.user = current_user

    authorize_purchase_create!

    created = ListItem.transaction do
      @list_item.lock!

      @purchase.save
    end

    if created
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "purchases/update", locals: { message: t(".success") }, status: :created
        end
        format.html do
          redirect_to user_list_url(@list.user, @list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "purchases/error", locals: { message: t(".error"), list: @list, list_item: @list_item, purchase: @purchase }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def update
    @purchase = find_purchase

    @list_item = @purchase.list_item

    @list = @list_item.list

    authorize_purchase_update!

    updated = ListItem.transaction do
      @list_item.lock!

      @purchase.update(purchase_params)
    end

    if updated
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "purchases/update", locals: { message: t(".success") }
        end
        format.html do
          redirect_to user_list_url(@list.user, @list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "purchases/error", locals: { message: t(".error"), list: @list, list_item: @list_item, purchase: @purchase }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def destroy
    @purchase = find_purchase

    @list_item = @purchase.list_item

    @list = @list_item.list

    authorize_purchase_destroy!

    destroyed = ListItem.transaction do
      @list_item.lock!

      @purchase.destroy
    end

    if destroyed
      load_list_items

      respond_to do |format|
        format.turbo_stream do
          render "purchases/update", locals: { message: t(".success") }
        end
        format.html do
          redirect_to user_list_url(@list.user, @list), status: :see_other
        end
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render "purchases/error", locals: { message: t(".error") }, status: :unprocessable_entity
        end
        format.html do
          load_list_items

          flash.now[:error] = t(".error")

          render "lists/show", status: :unprocessable_entity
        end
      end
    end
  end

  def owner
    @owner ||= User.friendly.find(params[:user_id])
  end
  helper_method :owner

  private

  def authorize_purchase_create!
    raise ActiveRecord::RecordNotFound if @list.user == current_user
  end

  def authorize_purchase_update!
    raise ActiveRecord::RecordNotFound unless @purchase.editable_by?(current_user)
  end

  def authorize_purchase_destroy!
    raise ActiveRecord::RecordNotFound unless @purchase.deletable_by?(current_user)
  end

  def find_list
    owner.lists.publicly_visible.friendly.find(params[:list_id])
  end

  def find_list_item
    find_list.list_items.find(list_item_id_param)
  end

  def find_purchase
    find_list.purchases.find(params[:id])
  end

  def load_list_items
    @list_items = @list.list_items.visible_to(current_user).ordered.includes(:purchases)

    @list_items_by_priority = @list_items.group_by(&:priority)
  end

  def list_item_id_param
    params.require(:purchase).permit(:list_item_id)[:list_item_id]
  end

  def purchase_params
    params.require(:purchase).permit(:purchased_from, :notes, :price, :quantity, :reveal_at, :anonymous)
  end
end
