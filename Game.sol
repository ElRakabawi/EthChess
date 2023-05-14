// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract TurnBasedGame {
    event GameEnded(bytes32 indexed gameId);
    event GameClosed(bytes32 indexed gameId, address indexed player);
    event GameTimeoutStarted(bytes32 indexed gameId, uint timeoutStarted, int8 timeoutState);
    // GameDrawOfferRejected: notification that a draw of the currently turning player
    //                        is rejected by the waiting player
    event GameDrawOfferRejected(bytes32 indexed gameId);

    struct Game {
        address player1;
        address player2;
        string player1Alias;
        string player2Alias;
        address nextPlayer;
        address winner;
        bool ended;
        uint pot; // What this game is worth: ether paid into the game
        uint player1Winnings;
        uint player2Winnings;
        uint turnTime; // in minutes
        uint timeoutStarted; // timer for timeout
        /*
         * -2 draw offered by nextPlayer
         * -1 draw offered by waiting player
         * 0 nothing
         * 1 checkmate
         * 2 timeout
         */
        int8 timeoutState;
    }

    mapping (bytes32 => Game) public games;

    // stack of open game ids
    mapping (bytes32 => bytes32) public openGameIds;
    bytes32 public head;

    // stack of games of players
    mapping (address => mapping (bytes32 => bytes32)) public gamesOfPlayers;
    mapping (address => bytes32) public gamesOfPlayersHeads;

    function getGamesOfPlayer(address player) view public returns (bytes32[] memory) {
        bytes32 playerHead = gamesOfPlayersHeads[player];
        uint counter = 0;
        for (bytes32 ga = playerHead; ga != 0; ga = gamesOfPlayers[player][ga]) {
            counter++;
        }
        bytes32[] memory data = new bytes32[](counter);
        bytes32 currentGame = playerHead;
        for (uint i = 0; i < counter; i++) {
            data[i] = currentGame;
            currentGame = gamesOfPlayers[player][currentGame];
        }
        return data;
    }

    function getOpenGameIds() public view returns (bytes32[] memory) {
        uint counter = 0;
        for (bytes32 ga = head; ga != 'end'; ga = openGameIds[ga]) {
            counter++;
        }
        bytes32[] memory data = new bytes32[](counter);
        bytes32 currentGame = head;
        for (uint i = 0; i < counter; i++) {
            data[i] = currentGame;
            currentGame = openGameIds[currentGame];
        }
        return data;
    }

    // closes a game that is not currently running
    function closePlayerGame(bytes32 gameId) public {
        Game memory game = games[gameId];

        // game already started and not finished yet
        if (!(game.player2 == address(0) || game.ended))
            revert();
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        if (!game.ended)
            games[gameId].ended = true;

        if (game.player2 == address(0)) {
            // Remove from openGameIds
            if (head == gameId) {
                head = openGameIds[head];
                openGameIds[gameId] = 0;
            } else {
                for (bytes32 g = head; g != 'end' && openGameIds[g] != 'end'; g = openGameIds[g]) {
                    if (openGameIds[g] == gameId) {
                        openGameIds[g] = openGameIds[gameId];
                        openGameIds[gameId] = 0;
                        break;
                    }
                }
            }
            games[gameId].player1Winnings = games[gameId].pot;
            games[gameId].pot = 0;
        }

        // Remove from gamesOfPlayers
        bytes32 playerHead = gamesOfPlayersHeads[msg.sender];
        if (playerHead == gameId) {
            gamesOfPlayersHeads[msg.sender] = gamesOfPlayers[msg.sender][playerHead];

            gamesOfPlayers[msg.sender][head] = 0;
        } else {
            for (bytes32 ga = playerHead; ga != 0 && gamesOfPlayers[msg.sender][ga] != 'end';
                    ga = gamesOfPlayers[msg.sender][ga]) {
                if (gamesOfPlayers[msg.sender][ga] == gameId) {
                    gamesOfPlayers[msg.sender][ga] = gamesOfPlayers[msg.sender][gameId];
                    gamesOfPlayers[msg.sender][gameId] = 0;
                    break;
                }
            }
        }

        emit GameClosed(gameId, msg.sender);
    }

    /**
     * Surrender = unilateral declaration of loss
     */
    function surrender(bytes32 gameId) notEnded(gameId) public virtual {
        if (games[gameId].winner != address(0)) {
            // Game already ended
            revert();
        }
        if (games[gameId].player1 == msg.sender) {
            // Player 1 surrendered, player 2 won
            games[gameId].winner = games[gameId].player2;
            games[gameId].player2Winnings = games[gameId].pot;
            games[gameId].pot = 0;
        } else if(games[gameId].player2 == msg.sender) {
            // Player 2 surrendered, player 1 won
            games[gameId].winner = games[gameId].player1;
            games[gameId].player1Winnings = games[gameId].pot;
            games[gameId].pot = 0;
        } else {
            // Sender is not a participant of this game
            revert();
        }

        games[gameId].ended = true;
        emit GameEnded(gameId);
    }

    /**
     * Allows the winner of a game to withdraw their ether
     * bytes32 gameId: ID of the game they have won
     */
    function withdraw(bytes32 gameId) public payable {
        uint payout = 0;
        if(games[gameId].player1 == msg.sender && games[gameId].player1Winnings > 0) {
            payout = games[gameId].player1Winnings;
            games[gameId].player1Winnings = 0;
            if (!payable(msg.sender).send(payout)) {
                revert();
            }
        }
        else if(games[gameId].player2 == msg.sender && games[gameId].player2Winnings > 0) {
            payout = games[gameId].player2Winnings;
            games[gameId].player2Winnings = 0;
            if (!payable(msg.sender).send(payout)) {
                revert();
            }
        }
        else {
            revert();
        }
    }

    function isGameEnded(bytes32 gameId) public view returns (bool) {
        return games[gameId].ended;
    }

    modifier notEnded(bytes32 gameId) {
        if (games[gameId].ended) revert('Game Ended');
        _;
    }

    function initGame(string memory player1Alias, uint turnTime) payable public returns (bytes32) {
        if (turnTime < 5)
            revert();

        // Generate game id based on player's addresses and current block number
        bytes32 gameId = keccak256(abi.encodePacked(msg.sender, block.number));

        games[gameId].ended = false;
        games[gameId].turnTime = turnTime;
        games[gameId].timeoutState = 0;

        // Initialize participants
        games[gameId].player1 = msg.sender;
        games[gameId].player1Alias = player1Alias;
        games[gameId].player1Winnings = 0;
        games[gameId].player2Winnings = 0;

        // Initialize game value
        games[gameId].pot = msg.value * 2;

        // Add game to gamesOfPlayers
        gamesOfPlayers[msg.sender][gameId] = gamesOfPlayersHeads[msg.sender];
        gamesOfPlayersHeads[msg.sender] = gameId;

        // Add to openGameIds
        openGameIds[gameId] = head;
        head = gameId;

        return gameId;
    }

    /**
     * Join an initialized game
     * bytes32 gameId: ID of the game to join
     * string player2Alias: Alias of the player that is joining
     */
    function joinGame(bytes32 gameId, string memory player2Alias) payable public virtual {
        // Check that this game does not have a second player yet
        if (games[gameId].player2 != address(0)) {
            revert();
        }

        // revert() if the second player did not match the bet.
        if (msg.value != games[gameId].pot) {
            revert();
        }
        games[gameId].pot += msg.value;

        games[gameId].player2 = msg.sender;
        games[gameId].player2Alias = player2Alias;

        // Add game to gamesOfPlayers
        gamesOfPlayers[msg.sender][gameId] = gamesOfPlayersHeads[msg.sender];
        gamesOfPlayersHeads[msg.sender] = gameId;

        // Remove from openGameIds
        if (head == gameId) {
            head = openGameIds[head];
            openGameIds[gameId] = 0;
        } else {
            for (bytes32 g = head; g != 'end' && openGameIds[g] != 'end'; g = openGameIds[g]) {
                if (openGameIds[g] == gameId) {
                    openGameIds[g] = openGameIds[gameId];
                    openGameIds[gameId] = 0;
                    break;
                }
            }
        }
    }

    /* The sender claims he has won the game. Starts a timeout. */
    function claimWin(bytes32 gameId) notEnded(gameId) public virtual {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        // only if timeout has not started
        if (game.timeoutState != 0)
            revert();
        // you can only claim draw / victory in the enemies turn
        if (msg.sender == game.nextPlayer)
            revert();

        game.timeoutStarted = block.timestamp;
        game.timeoutState = 1;
        emit GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /* The sender offers the other player a draw. Starts a timeout. */
    function offerDraw(bytes32 gameId) notEnded(gameId) public {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        // only if timeout has not started or is a draw by nextPlayer
        if (game.timeoutState != 0 && game.timeoutState != 2)
            revert();
        // if state = timeout, timeout has to be 2*timeoutTime
        if (game.timeoutState == 2 && block.timestamp < game.timeoutStarted + 2 * game.turnTime * 1 minutes)
            revert();

        if (msg.sender == game.nextPlayer) {
            game.timeoutState = -2;
        } else {
            game.timeoutState = -1;
        }
        game.timeoutStarted = block.timestamp;
        emit GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /*
     * The sender claims that the other player is not in the game anymore.
     * Starts a Timeout that can be claimed
     */
    function claimTimeout(bytes32 gameId) notEnded(gameId) public virtual {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        // only if timeout has not started
        if (game.timeoutState != 0)
            revert();
        // you can only claim draw / victory in the enemies turn
        if (msg.sender == game.nextPlayer)
            revert();
        game.timeoutStarted = block.timestamp;
        game.timeoutState = 2;
        emit GameTimeoutStarted(gameId, game.timeoutStarted, game.timeoutState);
    }

    /*
     * The sender (waiting player) rejects the draw offered by the
     * other (turning / current) player.
     */
    function rejectCurrentPlayerDraw(bytes32 gameId) notEnded(gameId) public {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        // only if timeout is present
        if (game.timeoutState != -2)
            revert();
        // only not playing player is able to reject a draw offer of the nextPlayer
        if (msg.sender == game.nextPlayer)
            revert();
        game.timeoutState = 0;
        emit GameDrawOfferRejected(gameId);
    }

    /* The sender claims a previously started timeout. */
    function claimTimeoutEnded(bytes32 gameId) notEnded(gameId) public virtual {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        if (game.timeoutState == 0 || game.timeoutState == 2)
            revert();
        if (block.timestamp < game.timeoutStarted + game.turnTime * 1 minutes)
            revert();
        if (msg.sender == game.nextPlayer) {
            if (game.timeoutState == -2) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                emit GameEnded(gameId);
            } else {
                revert();
            }
        } else {
            if (game.timeoutState == -1) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                emit GameEnded(gameId);
            } else if (game.timeoutState == 1){ // win
                game.ended = true;
                game.winner = msg.sender;
                if(msg.sender == game.player1) {
                    games[gameId].player1Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                } else {
                    games[gameId].player2Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                }
                emit GameEnded(gameId);
            } else {
                revert();
            }
        }
    }

    /* A timeout can be confirmed by the non-initializing player. */
    function confirmGameEnded(bytes32 gameId) notEnded(gameId) public virtual {
        Game memory game = games[gameId];
        // just the two players currently playing
        if (msg.sender != game.player1 && msg.sender != game.player2)
            revert();
        if (game.timeoutState == 0)
            revert();
        if (msg.sender != game.nextPlayer) {
            if (game.timeoutState == -2) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                emit GameEnded(gameId);
            } else {
                revert();
            }
        } else {
            if (game.timeoutState == -1) { // draw
                game.ended = true;
                games[gameId].player1Winnings = games[gameId].pot / 2;
                games[gameId].player2Winnings = games[gameId].pot / 2;
                games[gameId].pot = 0;
                emit GameEnded(gameId);
            } else if (game.timeoutState == 1 || game.timeoutState == 2) { // win
                game.ended = true;
                if(msg.sender == game.player1) {
                    game.winner = game.player2;
                    games[gameId].player2Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                } else {
                    game.winner = game.player1;
                    games[gameId].player1Winnings = games[gameId].pot;
                    games[gameId].pot = 0;
                }
                emit GameEnded(gameId);
            } else {
                revert();
            }
        }
    }
}