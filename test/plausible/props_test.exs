defmodule Plausible.PropsTest do
  use Plausible.DataCase

  test "allow/2 adds props to the array" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-2")

    assert %Plausible.Site{allowed_event_props: ["my-prop-2", "my-prop-1"]} =
             Plausible.Repo.reload!(site)
  end

  test "allow/2 takes a single prop or multiple" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert {:ok, site} = Plausible.Props.allow(site, ["my-prop-3", "my-prop-2"])

    assert %Plausible.Site{allowed_event_props: ["my-prop-3", "my-prop-2", "my-prop-1"]} =
             Plausible.Repo.reload!(site)
  end

  test "allow/2 trims trailing whitespaces" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "   my-prop-1 ")
    assert %Plausible.Site{allowed_event_props: ["my-prop-1"]} = Plausible.Repo.reload!(site)
  end

  test "allow/2 fails when prop list is too long" do
    site = insert(:site)
    props = for i <- 1..300, do: "my-prop-#{i}"

    assert {:ok, site} = Plausible.Props.allow(site, props)
    assert {:error, changeset} = Plausible.Props.allow(site, "my-prop-301")

    assert {"should have at most %{count} item(s)",
            [count: 300, validation: :length, kind: :max, type: :list]} ==
             changeset.errors[:allowed_event_props]
  end

  test "allow/2 fails when prop key is too long" do
    site = insert(:site)

    long_prop = String.duplicate("a", 301)
    assert {:error, changeset} = Plausible.Props.allow(site, long_prop)
    assert {"must be between 1 and 300 characters", []} == changeset.errors[:allowed_event_props]
  end

  test "allow/2 fails when prop key is empty" do
    site = insert(:site)

    assert {:error, changeset} = Plausible.Props.allow(site, "")
    assert {"must be between 1 and 300 characters", []} == changeset.errors[:allowed_event_props]

    assert {:error, changeset} = Plausible.Props.allow(site, " ")
    assert {"must be between 1 and 300 characters", []} == changeset.errors[:allowed_event_props]
  end

  test "allow/2 does not fail when prop key is already in the list" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert %Plausible.Site{allowed_event_props: ["my-prop-1"]} = Plausible.Repo.reload!(site)
  end

  test "disallow/2 removes the prop from the array" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-2")
    assert {:ok, site} = Plausible.Props.disallow(site, "my-prop-2")
    assert %Plausible.Site{allowed_event_props: ["my-prop-1"]} = Plausible.Repo.reload!(site)
  end

  test "disallow/2 does not fail when prop is not in the list" do
    site = insert(:site)

    assert {:ok, site} = Plausible.Props.allow(site, "my-prop-1")
    assert {:ok, site} = Plausible.Props.disallow(site, "my-prop-2")
    assert %Plausible.Site{allowed_event_props: ["my-prop-1"]} = Plausible.Repo.reload!(site)
  end

  test "allow_existing_props/1 saves the most frequent prop keys" do
    site = insert(:site)

    populate_stats(site, [
      build(:event,
        name: "Payment",
        "meta.key": ["amount"],
        "meta.value": ["500"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "logged_in"],
        "meta.value": ["100", "false"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "is_customer"],
        "meta.value": ["100", "false"]
      )
    ])

    {:ok, site} = Plausible.Props.allow_existing_props(site)

    assert %Plausible.Site{allowed_event_props: ["amount", "logged_in", "is_customer"]} =
             Plausible.Repo.reload!(site)
  end

  test "allow_existing_props/1 skips invalid keys" do
    site = insert(:site)

    populate_stats(site, [
      build(:event,
        name: "Payment",
        "meta.key": ["amount", String.duplicate("a", 301)],
        "meta.value": ["500", "true"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "logged_in"],
        "meta.value": ["100", "false"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "is_customer"],
        "meta.value": ["100", "false"]
      )
    ])

    {:ok, site} = Plausible.Props.allow_existing_props(site)

    assert %Plausible.Site{allowed_event_props: ["amount", "logged_in", "is_customer"]} =
             Plausible.Repo.reload!(site)
  end

  test "allow_existing_props/1 can be run multiple times" do
    site = insert(:site)

    populate_stats(site, [
      build(:event,
        name: "Payment",
        "meta.key": ["amount"],
        "meta.value": ["500"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "logged_in"],
        "meta.value": ["100", "false"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "is_customer"],
        "meta.value": ["100", "false"]
      )
    ])

    {:ok, %Plausible.Site{allowed_event_props: ["amount", "logged_in", "is_customer"]}} =
      Plausible.Props.allow_existing_props(site)

    populate_stats(site, [
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "os"],
        "meta.value": ["500", "Windows"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "logged_in", "with_error"],
        "meta.value": ["100", "false", "true"]
      ),
      build(:event,
        name: "Payment",
        "meta.key": ["amount", "is_customer", "first_time_customer"],
        "meta.value": ["100", "false", "true"]
      )
    ])

    {:ok,
     %Plausible.Site{
       allowed_event_props: [
         "amount",
         "logged_in",
         "is_customer",
         "os",
         "with_error",
         "first_time_customer"
       ]
     }} = Plausible.Props.allow_existing_props(site)
  end
end
