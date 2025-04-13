alias MtgDraftServer.Repo
alias MtgDraftServer.Cards.Card
alias MtgDraftServer.Cards.CardMetadata

# Define a function to process card faces as an anonymous function
process_card_faces = fn card_attrs ->
  if Map.has_key?(card_attrs, "card_faces") and is_list(card_attrs["card_faces"]) and 
     length(card_attrs["card_faces"]) > 0 do
    
    # Get the first face for default values
    first_face = List.first(card_attrs["card_faces"])
    
    # Merge properties from the first face if they're missing in the main card
    card_attrs
    |> Map.put_new("mana_cost", first_face["mana_cost"])
    |> Map.put_new("type_line", first_face["type_line"])
    |> Map.put_new("oracle_text", first_face["oracle_text"])
    |> Map.put_new("colors", first_face["colors"])
    |> Map.put_new("power", first_face["power"])
    |> Map.put_new("toughness", first_face["toughness"])
    |> Map.put_new("image_uris", first_face["image_uris"])
  else
    card_attrs
  end
end

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

  # Process card faces before inserting
  card_attrs = process_card_faces.(card_attrs)

  # Insert the card
  {:ok, card} = 
    %Card{}
    |> Card.changeset(card_attrs)
    |> Repo.insert(on_conflict: :nothing)

  # Now insert the metadata
  %CardMetadata{}
  |> CardMetadata.changeset(%{
    card_id: card.id,
    layout: Map.get(card_attrs, "layout", "normal"),
    is_token: Map.get(card_attrs, "is_token", false),
    is_digital: Map.get(card_attrs, "digital", false),
    is_promo: Map.get(card_attrs, "promo", false)
  })
  |> Repo.insert(on_conflict: :nothing)
end)