defmodule Tasky.Classes do
  @moduledoc """
  The Classes context.
  """

  import Ecto.Query, warn: false
  alias Tasky.Repo

  alias Tasky.Classes.Class

  @doc """
  Returns the list of classes.

  ## Examples

      iex> list_classes()
      [%Class{}, ...]

  """
  def list_classes do
    Repo.all(from c in Class, order_by: [asc: c.name])
  end

  @doc """
  Gets a single class.

  Raises `Ecto.NoResultsError` if the Class does not exist.

  ## Examples

      iex> get_class!(123)
      %Class{}

      iex> get_class!(456)
      ** (Ecto.NoResultsError)

  """
  def get_class!(id), do: Repo.get!(Class, id)

  @doc """
  Gets a class by slug.

  Returns `nil` if no class exists with the given slug.

  ## Examples

      iex> get_class_by_slug("klasse-5a")
      %Class{}

      iex> get_class_by_slug("unknown")
      nil

  """
  def get_class_by_slug(slug) when is_binary(slug) do
    Repo.get_by(Class, slug: slug)
  end

  @doc """
  Creates a class.

  ## Examples

      iex> create_class(%{field: value})
      {:ok, %Class{}}

      iex> create_class(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_class(attrs \\ %{}) do
    %Class{}
    |> Class.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a class.

  ## Examples

      iex> update_class(class, %{field: new_value})
      {:ok, %Class{}}

      iex> update_class(class, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_class(%Class{} = class, attrs) do
    class
    |> Class.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a class.

  ## Examples

      iex> delete_class(class)
      {:ok, %Class{}}

      iex> delete_class(class)
      {:error, %Ecto.Changeset{}}

  """
  def delete_class(%Class{} = class) do
    Repo.delete(class)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking class changes.

  ## Examples

      iex> change_class(class)
      %Ecto.Changeset{data: %Class{}}

  """
  def change_class(%Class{} = class, attrs \\ %{}) do
    Class.changeset(class, attrs)
  end

  @doc """
  Returns the count of students in a class.

  ## Examples

      iex> count_students_in_class(class)
      5

  """
  def count_students_in_class(%Class{id: class_id}) do
    Repo.one(
      from u in Tasky.Accounts.User,
        where: u.class_id == ^class_id,
        select: count(u.id)
    )
  end

  @doc """
  Returns a map of %{class_id => student_count} for all classes in a single query.

  ## Examples

      iex> count_students_per_class()
      %{1 => 5, 2 => 3}

  """
  def count_students_per_class do
    Repo.all(
      from u in Tasky.Accounts.User,
        where: not is_nil(u.class_id),
        group_by: u.class_id,
        select: {u.class_id, count(u.id)}
    )
    |> Map.new()
  end

  @doc """
  Returns the list of students in a class.

  ## Examples

      iex> list_students_in_class(class)
      [%User{}, ...]

  """
  def list_students_in_class(%Class{id: class_id}) do
    Repo.all(
      from u in Tasky.Accounts.User,
        where: u.class_id == ^class_id,
        order_by: [asc: u.lastname, asc: u.firstname]
    )
  end
end
