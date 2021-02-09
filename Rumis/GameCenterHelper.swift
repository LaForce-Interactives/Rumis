//
//  GameCenterHelper.swift
//  Rumis
//
//  Created by William Dong on 2021/1/20.
//

import GameKit

extension GKTurnBasedMatch {
    var localPlayer: Int{
        for i in 0..<participants.count{
            if participants[i].player == GKLocalPlayer.local{
                return i
            }
        }
        return -1
    }
    
    func sendTurn(game: Game, quit: Bool = false){
        do{
            let encodedState = try JSONEncoder().encode(game.state)
            let callback = GameCenterHelper.helper.syncCallback
            var cp = game.currentPlayer
            while cp != -1 && participants[cp].matchOutcome == .quit{ // append pass moves
                game.executeMove(move: [-1])
                cp = game.currentPlayer
            }
            if cp == -1{
                // Set outcomes
                let outcomes = game.outcomes()
                for i in 0...participants.count-1{
                    let part = participants[i]
                    if part.matchOutcome == .none{
                        part.matchOutcome = outcomes[i]
                    }
                }
                self.endMatchInTurn(withMatch: encodedState, completionHandler: callback("end game",self))
            }else{
                let nextpart = participants[cp]
                if quit{
                    self.participantQuitInTurn(
                        with: .quit,
                        nextParticipants: [nextpart],
                        turnTimeout: GKExchangeTimeoutNone,
                        match: encodedState,
                        completionHandler: callback("quit",self))
                }else if game.state.playerIDs[cp] == GKLocalPlayer.local.getID(){
                    self.saveCurrentTurn(withMatch: encodedState,
                                          completionHandler: callback("save turn",self))
                }else{
                    self.endTurn(
                        withNextParticipants: [nextpart],
                        turnTimeout: GKExchangeTimeoutNone,
                        match: encodedState,
                        completionHandler: callback("send turn",self)
                    )
                }
            }
        }catch{
            print("JSON encoder error")
        }
    }
}

extension GKPlayer{
    func getID() -> String{
        if #available(iOS 12.4, *) {
            return self.playerID
            // Note: gamePlayerID and teamPlayerID are not consistent as Apple states. 12/08/2020
        } else {
            return self.playerID
        }
    }
}

extension Game{
    func outcomes() -> [GKTurnBasedMatch.Outcome] {
        let s = self.getScores()
        if s.count == 2{
            if s[0] > s[1]{
                return [.won, .lost]
            }
            if s[0] < s[1]{
                return [.lost, .won]
            }
            return [.tied, .tied]
        }else{
            // TODO: Improve to handle ties?
            let idx = s.indices.sorted{s[$0]>s[$1]}
            let rank = s.indices.map{idx.firstIndex(of: $0)!}
            let outcomes: [GKTurnBasedMatch.Outcome] = [.first, .second, .third, .fourth]
            return rank.map{outcomes[$0]}
        }
    }
}

extension GKTurnBasedParticipant{
    func infoStr() -> String{
        var mes = "Participant:\n"
        mes = mes + "\tPlayer:\n"
        if player == nil{
            mes = mes + "\t\t<empty>\n"
        }else{
            mes = mes + "\t\tDisname:\(player!.displayName)\n"
            mes = mes + "\t\tAlias:\(player!.alias)\n"
            mes = mes + "\t\tIdentifier:\(player!.getID())\n"
        }
        mes = mes + "\tStatus:\(status.rawValue)\n"
        mes = mes + "\tOutcome:\(matchOutcome.rawValue)"
        return mes
    }
}

final class GameCenterHelper: NSObject {
    
    typealias CompletionBlock = (Error?) -> Void
    static let helper = GameCenterHelper()
    var viewController: ViewController?
    var currentMatchmakerVC: GKTurnBasedMatchmakerViewController?
    var currentMatch: GKTurnBasedMatch? // The current match displayed by viewcontroller
    
    static var isAuthenticated: Bool {
        return GKLocalPlayer.local.isAuthenticated
    }
    
    var canTakeTurnForCurrentMatch: Bool {
        guard let match = currentMatch else {
            return false
        }
        return match.currentParticipant?.player == GKLocalPlayer.local
    }
    
    enum GameCenterHelperError: Error {
        case matchNotFound
    }
    
    override init() {
        super.init()
        GKLocalPlayer.local.authenticateHandler = { gcAuthVC, error in
            if GKLocalPlayer.local.isAuthenticated {
                GKLocalPlayer.local.register(self)
            } else if let vc = gcAuthVC {
                self.viewController?.present(vc, animated: true)
            }
            else {
                print("Error authentication to GameCenter: " +
                    "\(error?.localizedDescription ?? "none")")
            }
        }
    }
    
    public func clearAllMatches(){
        GKTurnBasedMatch.loadMatches(completionHandler: {
            matches, error in
            guard let matches = matches else{
                print("no existing matches")
                return
            }
            for match in matches{
                match.remove(completionHandler: nil)
            }
            print("all match removed")
        })
    }
    
    func syncCallback(_ mes:String, match:GKTurnBasedMatch) -> (Error?) -> Void{
        // revert to state if sync failed
        return { error in
            guard let e = error else {return} // Success
            print("\(e.localizedDescription)")
            guard let vc = self.viewController else {return}
            if (match == self.currentMatch){
                if let gvc = vc.onlineGVC{
                    while gvc.game.currentPlayer != match.localPlayer {
                        gvc.Undo()
                        gvc.game.state.history.removeLast()
                    }
                }
            }
            let toastMes = "Network Error: Failed to \(mes)."
            vc.topVC.view.makeToast(toastMes)
            let alert=UIAlertController(title:"Network Error!", message: "Cannot \(mes)", preferredStyle: UIAlertController.Style.alert)
            let cancel=UIAlertAction(title: "OK", style: .cancel)
            alert.addAction(cancel)
            vc.topVC.present(alert, animated: true, completion: nil)
        }
    }
    
    func presentMatchmaker(n_players: Int, playerGroup: Int = 0, showMatches: Bool = false) {
        guard GKLocalPlayer.local.isAuthenticated else {
            viewController!.view.makeToast("Waiting for GameCenter authentication")
            return
        }
        print("Local ID:", GKLocalPlayer.local.getID())
        let request = GKMatchRequest()
        request.minPlayers = n_players
        request.maxPlayers = n_players
        request.playerGroup = playerGroup
        request.inviteMessage = "Let's play Rumis!"
        let vc = GKTurnBasedMatchmakerViewController(matchRequest: request)
        vc.showExistingMatches = showMatches
        vc.turnBasedMatchmakerDelegate = self
        currentMatchmakerVC = vc
        viewController!.present(vc, animated: true)
    }
    
    func presentTurnAlert(match: GKTurnBasedMatch, state: GameState){
        guard let vc = viewController else {return}
        let yourTurn = match.currentParticipant?.player == GKLocalPlayer.local
        let title = yourTurn ? "Your Turn!" : "There's update!"
        var n_free: Int = 0
        var names:[String] = [] // All other names except the local player
        for part in match.participants{
            if part.player != nil{
                if part.player!.getID() != GKLocalPlayer.local.getID(){
                    names.append(part.player!.displayName)
                }
            }else{
                n_free += 1
            }
        }
        var mes = "in an online game with "
        for i in 0...names.count-1{
            mes += names[i]
            if i<names.count-1{
                mes += ", "
            }
        }
        if n_free > 0{
            mes += "and \(n_free) matched players"
        }
        let alert=UIAlertController(title:title, message: mes, preferredStyle: UIAlertController.Style.alert)
        let ac = UIAlertAction(title: "Go to game", style: .default){ _ in
            self.currentMatch = match
            self.viewController!.presentGame(state: state, online: true)
        }
        alert.addAction(ac)
        let cancel=UIAlertAction(title: "OK", style: .cancel)
        alert.addAction(cancel)
        vc.topVC.present(alert, animated: true, completion: nil)
    }
}

extension Notification.Name {
    static let presentGame = Notification.Name(rawValue: "presentGame")
    static let authenticationChanged = Notification.Name(rawValue: "authenticationChanged")
}

extension GameCenterHelper: GKTurnBasedMatchmakerViewControllerDelegate {
    func turnBasedMatchmakerViewControllerWasCancelled(
        _ viewController: GKTurnBasedMatchmakerViewController) {
        viewController.dismiss(animated: true)
    }
    
    func turnBasedMatchmakerViewController(
        _ viewController: GKTurnBasedMatchmakerViewController,
        didFailWithError error: Error) {
        print("Matchmaker vc did fail with error: \(error.localizedDescription).")
    }
}

extension GameCenterHelper: GKLocalPlayerListener {
    func player(_ player: GKPlayer, wantsToQuitMatch match: GKTurnBasedMatch) {
        print(player.displayName, "WANTS TO QUIT")
        assert(player == GKLocalPlayer.local) // only calls on local player
        assert(player.getID() == match.currentParticipant!.player!.getID()) // only calls in turn
        match.loadMatchData{ data, error in
            var state: GameState
            if let data = data {
                do {
                    state = try JSONDecoder().decode(GameState.self, from: data)
                } catch {
                    fatalError("A game to quit should not be empty")
                }
            } else {
                print("Load match data error: \(error!.localizedDescription)")
                return
            }
            
            let game = Game(state: state)
            while game.turnNumber < game.state.history.count {
                game.replayStep()
            }
            game.executeMove(move: [-1])
            match.currentParticipant!.matchOutcome = .quit
            match.sendTurn(game: game, quit: true)
        }
    }
    
    func gotUpdateForMatch(_ match: GKTurnBasedMatch, didBecomeActive: Bool){
        for part in match.participants{
            if part == match.currentParticipant{
                print("current:")
            }
            print(part.infoStr())
        }
        print("========")
        
        if let vc = currentMatchmakerVC {
            currentMatchmakerVC = nil
            vc.dismiss(animated: true)
        }
        
        guard let vc = viewController else {
            return
        }
        match.loadMatchData { data, error in
            let state: GameState
            if let data = data {
                do {
                    state = try JSONDecoder().decode(GameState.self, from: data)
                } catch {
                    print("new game")
                    let n = match.participants.count
                    let name = self.viewController!.getMapName()
                    state = GameState(n_player: n, mapName: name)
                }
            } else {
                print("\(error!.localizedDescription)")
                return
            }
            
            let cm = GameCenterHelper.helper.currentMatch
            let sameMatch = cm == nil ? false : cm!.matchID == match.matchID
            if sameMatch{ // currentMatch is only assigned here or when presenting onlineGVC
                GameCenterHelper.helper.currentMatch = match
                vc.onlineGVC!.game.state = state
            }
            let showing = sameMatch && vc.topVC == vc.onlineGVC
            if showing{
                vc.onlineGVC!.FastForwardView()
            }else{
                if (didBecomeActive){
                    self.currentMatch = match
                    self.viewController!.presentGame(state: state, online: true)
                }else{
                    self.presentTurnAlert(match: match, state: state)
                }
            }
        }
    }
    
    func player(_ player: GKPlayer, matchEnded match: GKTurnBasedMatch) {
        assert(player == GKLocalPlayer.local)
        print("match ended")
        self.gotUpdateForMatch(match, didBecomeActive: false)
    }
    
    func player(_ player: GKPlayer, receivedTurnEventFor match: GKTurnBasedMatch, didBecomeActive: Bool){
        assert(player == GKLocalPlayer.local)
        print("receiveTurnEvent \(didBecomeActive)")
//        viewController!.view.makeToast("receiveTurnEvent \(didBecomeActive)")
        self.gotUpdateForMatch(match, didBecomeActive: didBecomeActive)
    }
}
