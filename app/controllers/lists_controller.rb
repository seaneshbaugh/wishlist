class ListsController < ApplicationController
  def index
    @lists = visible_lists
  end

  def show
    @list = find_list
  end

  def new
    @list = List.new
  end

  def create
    @list = current_user.lists.build(list_params)

    if @list.save
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
      flash[:error] = t(".error")

      render "show", status:  :unprocessable_entity
    end
  end

  def owner
    @owner ||= begin
      if params[:user_id]
        User.friendly.find(params[:user_id])
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

  def list_params
    params.require(:list).permit(:name, :description, :order, :public)
  end
end
