--!strict
-- Onboarding steps (server-owned). Icons carry the meaning; text is a short hint.

export type Step = {
	id: string,
	hint: string,
	icon: string, -- key into config/Assets icons
	reward: { coins: number }?,
}

return table.freeze({
	starterNest = "starter",
	steps = {
		{ id = "plant", hint = "Tap a nest bed", icon = "nest" },
		{ id = "hatch", hint = "Hatch!", icon = "hatch" },
		{ id = "habitat", hint = "Place your critter", icon = "habitat" },
		{ id = "reward", hint = "Open your gift", icon = "gift", reward = { coins = 100 } },
		{ id = "buy", hint = "Buy a nest", icon = "shop" },
		{ id = "plant2", hint = "Plant it", icon = "nest", reward = { coins = 150 } },
	} :: { Step },
})
