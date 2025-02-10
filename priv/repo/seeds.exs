alias MtgDraftServer.Repo
alias MtgDraftServer.Cards.Card

"priv/repo/data/oracle_cards.json"
|> File.read!()
|> Jason.decode!()
|> Enum.each(fn card_attrs ->
  # Map the "set" key to "set_code" if it exists.
  card_attrs =
    if Map.has_key?(card_attrs, "set") do
      Map.put(card_attrs, "set_code", card_attrs["set"])
    else
      card_attrs
    end

  %Card{}
  |> Card.changeset(card_attrs)
  |> Repo.insert!(on_conflict: :nothing)
end)
