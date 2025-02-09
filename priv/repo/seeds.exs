# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     MtgDraftServer.Repo.insert!(%MtgDraftServer.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.
# priv/repo/seeds.exs
alias MtgDraftServer.Repo
alias MtgDraftServer.Cards.Card

# Adjust the path to your JSON file
"priv/repo/data/oracle_cards.json"
|> File.read!()
|> Jason.decode!()
|> Enum.each(fn card_attrs ->
  # Note: the keys in the JSON are strings. Your changeset above expects those keys.
  %Card{}
  |> Card.changeset(card_attrs)
  |> Repo.insert!()
end)
