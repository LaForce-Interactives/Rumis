//
//  ViewController.swift
//  Rumis
//
//  Created by William Dong on 2021/1/15.
//

import Foundation
import UIKit

class ViewController: UIViewController{
    @IBOutlet var numPlayerSeg: UISegmentedControl!
    @IBOutlet var mapNameSeg: UISegmentedControl!
    @IBOutlet var localOnlineSeg: UISegmentedControl!
    
    public var localGVC: GameViewController? = nil
    public var onlineGVC: GameViewController? = nil
    
    var topVC: UIViewController{
        for vc in [localGVC, onlineGVC, GameCenterHelper.helper.currentMatchmakerVC]{
            // This order is important
            guard let vc = vc else {continue}
            if vc.presentingViewController == self{
                return vc
            }
        }
        return self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        GameCenterHelper.helper.viewController = self
    }
    
    func getMapName() -> String{
        let i_map = mapNameSeg.selectedSegmentIndex
        if i_map == 0{ // Random map
            return ["Tower", "Corner", "Steps", "Pyramid"][Int.random(in: 0...3)]
        }else{
            return mapNameSeg.titleForSegment(at: i_map)!
        }
    }
    
    @IBAction func NewGame(){
        let n = numPlayerSeg.selectedSegmentIndex+2
        let i_map = mapNameSeg.selectedSegmentIndex
        if localOnlineSeg.selectedSegmentIndex == 0{ // new local game
            let name = getMapName()
            let state = GameState(n_player: n, mapName: name)
            if localGVC != nil && localGVC!.game.currentPlayer != -1{
                let mes = "Starting a new local game will discard the ongoing local game. Are you sure?"
                let alert=UIAlertController(title:"Warning", message: mes, preferredStyle: UIAlertController.Style.alert)
                let cancel=UIAlertAction(title: "Cancel", style: .cancel)
                alert.addAction(cancel)
                let ac = UIAlertAction(title: "Yes", style: .default){ _ in
                    self.presentGame(state: state)
                }
                alert.addAction(ac)
                present(alert, animated: true, completion: nil)
            }else{
                presentGame(state: state)
            }
        }else{ // new online game
            GameCenterHelper.helper.presentMatchmaker(n_players: n, playerGroup: i_map, showMatches: false)
        }
    }
    
    @IBAction func ContinueLocalGame(){
        if let gvc = localGVC{
            presentGVC(gvc: gvc)
        }else{
            view.makeToast("No existing local game")
        }
    }
    
    @IBAction func ContinueOnlineGame(){
        if let gvc = onlineGVC{
            presentGVC(gvc: gvc)
        }else{
            view.makeToast("No existing online game")
        }
    }
    
    @IBAction func ViewOnlineGames(){
        GameCenterHelper.helper.presentMatchmaker(n_players: 2, playerGroup: 0, showMatches: true)
    }
    
    @IBAction func ClearMatches(){
        GameCenterHelper.helper.clearAllMatches()
    }
    
    func presentGame(state:GameState, online:Bool = false) -> Void{
        let game = Game(state: state)
        game.isOnline = online
        let gvc = GameViewController.loadFromStoryboard()
        gvc.game = game
        presentGVC(gvc: gvc)
    }
    
    func presentGVC(gvc: GameViewController) -> Void{
        if topVC != self{
            topVC.dismiss(animated: true){
                if gvc.presentingViewController != self{
                    self.present(gvc, animated:true)
                    print("done dismiss then present")
                }else{
                    print("race condition resolved")
                }
            }
        }else{
            self.present(gvc, animated:true)
            print("done directly present")
        }
        if gvc.game.isOnline{
            self.onlineGVC = gvc
        }else{
            self.localGVC = gvc
        }
    }
    
    func updateGame(state: GameState) -> Void{
        // update an online game on the current gameview
        guard let gvc = self.onlineGVC else{
            return
        }
        gvc.game.state = state
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .portrait
        } else {
            return .all
        }
    }
}
