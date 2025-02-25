# GameJoiner.gd
extends Node

signal game_joined(game_data)
signal join_failed(reason)

const AVAILABLE_STAKES = [1000, 3000, 5000, 10000]

# Game types and their availability
var available_game_types = {
	"NL Hold'em Cash Game": true,
	"Pot Limit Omaha Cash Game": false,  # Not implemented yet
	"Jackpot SNG": true,
	"Multi Table Tournament": false  # Not implemented yet
}

func _ready():
	# Ensure minimum tables exist for each stake level
	for stake in AVAILABLE_STAKES:
		TableManager.ensure_minimum_tables(stake)

func get_game_types() -> Array:
	return available_game_types.keys()

func get_stakes(game_type: String) -> Array:
	if game_type in available_game_types and available_game_types[game_type]:
		return AVAILABLE_STAKES
	return []

func join_game(player_data: Dictionary, game_type: String, stake: int) -> void:
	print("Debug: Join game called with:")
	print("- Game type:", game_type)
	print("- Stake:", stake)
	print("- Player data:", player_data)
	
	# Validate game type
	if not game_type in available_game_types:
		emit_signal("join_failed", "Invalid game type")
		return
	
	if not available_game_types[game_type]:
		emit_signal("join_failed", "Game type not available")
		return
	
	# Convert stake to int for comparison
	var stake_int = int(stake)
	if stake_int not in AVAILABLE_STAKES:
		emit_signal("join_failed", "Invalid stake level")
		return
	
	# Calculate required stack
	var required_stack = stake_int * 100  # 100 big blinds minimum
	
	# Wait for balance initialization if needed
	if not PlayerData.is_balance_initialized:
		await PlayerData.balance_initialized
	
	# Check balance
	if not PlayerData.has_sufficient_balance(required_stack):
		emit_signal("join_failed", "Insufficient balance for this stake level")
		return
	
	# Set up player data for the table
	var table_player_data = {
		"user_id": User.current_user_id,
		"name": PlayerData.player_data["name"],
		"chips": required_stack,  # Starting stack is exactly 100 BB
		"bet": 0,
		"folded": false,
		"sitting_out": false,
		"cards": [],
		"auto_post_blinds": true,
		"last_action": "",
		"last_action_amount": 0,
		"time_bank": 30.0,
		"avatar_data": PlayerData.get_avatar_data()
	}
	
	# Find optimal table
	var table = TableManager.find_optimal_table(stake_int, table_player_data)
	if not table:
		emit_signal("join_failed", "No suitable table available")
		return
	
	# Try to seat the player
	var seat_index = TableManager.seat_player(table.id, table_player_data)
	if seat_index == -1:
		emit_signal("join_failed", "Failed to seat player")
		return
	
	# Update player's table balance
	PlayerData.player_data["total_balance"] -= required_stack
	
	# Prepare game data for client
	var game_data = {
		"table_id": table.id,
		"stake_level": stake_int,
		"seat_index": seat_index,
		"player_stack": required_stack,
		"min_buyin": table.min_buyin,
		"max_buyin": table.max_buyin,
		"game_type": game_type,
		"table_state": TableManager.get_table_data(table.id)
	}
	
	# Store in GameData for scene transition
	GameData.set_game_data(game_data)
	
	print("Debug: Successfully joined table:", table.id)
	emit_signal("game_joined", game_data)

func get_available_stakes_for_balance(game_type: String) -> Array:
	if not available_game_types.get(game_type, false):
		return []
		
	var available_stakes = []
	var current_balance = PlayerData.get_balance()
	
	for stake in AVAILABLE_STAKES:
		var required_stack = stake * 100  # 100 big blinds
		if current_balance >= required_stack:
			available_stakes.append(stake)
	
	return available_stakes

func is_stake_available(stake: int) -> bool:
	var required_stack = stake * 100
	return PlayerData.has_sufficient_balance(required_stack)
