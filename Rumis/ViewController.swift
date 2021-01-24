//
//  ViewController.swift
//  Rumis
//
//  Created by William Dong on 2021/1/15.
//

import Foundation
import UIKit

class ViewController: UIViewController{
    @IBOutlet var numPlayerSeg: UISegmentedControl?
    @IBOutlet var mapNameSeg: UISegmentedControl?
    @IBOutlet var localOnlineSeg: UISegmentedControl?
    
    @IBAction func myUnwindAction(unwindSegue: UIStoryboardSegue){
        
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        switch segue.identifier {
        case "local":
            let vc = segue.destination as! GameViewController
            let n = numPlayerSeg!.selectedSegmentIndex+2
            let i_map = mapNameSeg!.selectedSegmentIndex
            let mapName = mapNameSeg!.titleForSegment(at: i_map)!
            let state = GameState(n_player: n, mapName: mapName)
            vc.game = Game(state: state)
        default:
            break
        }
    }
}
