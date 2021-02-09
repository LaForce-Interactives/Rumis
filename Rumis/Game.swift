//
//  Game.swift
//  Rumis
//
//  Created by William Dong on 2021/1/12.
//

import Foundation
import UIKit

struct GameState: Codable {
    var numPlayers: Int
    var mapName: String // For Custom map
    var maxHeight: [[Int]] = []// height map
    var history: [[Int]] = []
    // list of moves (blockid, rx, ry, rz, rw, posX, posZ), -1 means pass
    var playerIDs: [String] // For online players and numplayer
    
    init(n_player: Int = 2, mapName: String = "Tower"){
        numPlayers = n_player
        playerIDs = Array(repeating: "", count: n_player)
        self.mapName = mapName
        switch mapName{
        case "Tower":
            if (n_player <= 4){
                let h = [4,6,8][n_player-2]
                maxHeight = Array(repeating: Array(repeating: h, count: 5), count: 4)
                // We will access maxHeight with (x,z) coord
            }
        case "Corner": // TODO: finish the rest maps
            if (n_player <= 4){
                let h = [2,3,4][n_player-2]
                maxHeight = Array(repeating: Array(repeating: h, count: 8), count: 6)
                for i in 3...5{
                    for j in 3...7{
                        maxHeight[i][j] = 0
                    }
                }
            }
        case "Steps":
            maxHeight = Array(repeating: Array(repeating: 0, count: 8), count: 8)
            let maxh = [4,5,8][n_player-2]
            for j in 0...7{
                for i in 3-j/2...4+j/2{
                    maxHeight[i][j] = min(maxh, 8-j)
                }
            }
        case "Pyramid":
            if (n_player == 2){
                maxHeight = Array(repeating: Array(repeating: 0, count: 4), count: 8)
                for i in 0...3{
                    for j in 0...3{
                        maxHeight[i][j] = 4-max(3-i,j)
                    }
                }
                for i in 4...7{
                    for j in 0...3{
                        maxHeight[i][j] = maxHeight[7-i][j]
                    }
                }
            }else{
                maxHeight = Array(repeating: Array(repeating: 0, count: 8), count: 8)
                for i in 0...7{
                    for j in 0...7{
                        maxHeight[i][j] = 4 - max(abs(2*i-7)/2,abs(2*j-7)/2)
                    }
                }
            }
            
        default:
            print("map unfound")
            assert(false)
        }
    }
    
    public var boardSize:[Int]{
        return [maxHeight.count, maxHeight[0].count]
    }
    
    public var boardCenterOffset:[Float]{
        return [Float(boardSize[0]-1)/2, Float(boardSize[1]-1)/2]
    }
}

class Game{
    var state: GameState
    var isOnline: Bool = false
    
    static let playerNames = ["Red", "Green", "Yellow", "Blue"]
    static let playerColors: [UIColor] = [.systemRed, .systemGreen, .systemYellow, .systemBlue]

    init(state: GameState) {
        self.state = state
        let L = state.maxHeight.count
        let W = state.maxHeight[0].count
        boardStatus = Array(repeating: Array(repeating: [], count: W), count: L)
        let n = state.numPlayers
        passed = Array(repeating: 0, count: n)
        blocksRemain = Array(repeating: Array(repeating: true, count: 11), count: n)
    }
    
    // Replayed by state
    var turnNumber: Int = 0 // Number of turns replayed
    var currentPlayer: Int = 0
    var boardStatus: [[[Int]]] // x, z, and list of ownerid from bottom to top
    var passed: [Int] // The order of player passes, 0 means not passed
    var blocksRemain: [[Bool]] // n_player by 11 bool
    func played(player i:Int) -> Bool{
        return blocksRemain[i].filter{!$0}.count > 0
    }
    
    func replayStep(){ // Move one step forward
        if (turnNumber >= state.history.count) {return}
        let move = state.history[turnNumber]
        if (move[0] == -1){
            passed[currentPlayer] = passed.max()!+1
        }else{
            let pts = pointsForMove(move: move)
            // Update board status
            for p in pts{
                let h = boardStatus[p[0]][p[2]].count
                if h <= p[1]{
                    for _ in h...p[1]{
                        boardStatus[p[0]][p[2]].append(currentPlayer)
                    }
                }
            }
            blocksRemain[currentPlayer][move[0]] = false
        }
        turnNumber += 1
        // next player
        let n = passed.count
        for i in 1...n{
            currentPlayer += 1
            if currentPlayer >= n { currentPlayer -= n }
            if passed[currentPlayer] == 0 { break }
            if i == n { currentPlayer = -1}
        }
    }
    
    func revertStep(){ // Move one step backward
        if turnNumber <= 0 { return }
        if currentPlayer == -1 { return }
        let move = state.history[turnNumber-1]
        if move[0] == -1{ // revert pass
            let i = passed.indices.max{passed[$0]<passed[$1]}!
            passed[i] = 0
        }else{
            let b = Block(id: move[0])
            b.setRotInts(rot: [move[1],move[2],move[3],move[4]])
            for p in b.points{
                boardStatus[p[0]+move[5]][p[2]+move[6]].removeLast()
            }
        }
        turnNumber -= 1
        // previous player
        let n = passed.count
        for _ in 1...n{
            currentPlayer -= 1
            if currentPlayer < 0 { currentPlayer += n }
            if passed[currentPlayer] == 0 { break }
        }
        if move[0] != -1{
            blocksRemain[currentPlayer][move[0]] = true
        }
    }
    
    func executeMove(move: [Int]){
        // Validity check
        if move.count == 0 { return }
        if move[0] == -1{
            assert(passed[currentPlayer] == 0)
        }else{
            assert(blocksRemain[currentPlayer][move[0]])
            assert(isValidMove(points: pointsForMove(move: move)) == "")
        }
        
        if turnNumber < state.history.count{
            state.history = Array(state.history[..<turnNumber])
            print("Warning: Undo-ed steps cleared.")
        }
        
        state.history.append(move)
        replayStep()
        if isOnline{
            GameCenterHelper.helper.currentMatch!.sendTurn(game: self)
        }
    }
    
    func pointsForMove(move: [Int]) -> [[Int]]{
        let b = Block(id: move[0], owner: currentPlayer)
        b.setRotInts(rot: [move[1],move[2],move[3],move[4]])
        let h0 = blockPosYInt(block: b, xz: [move[5],move[6]]) // posY of (0,0,0) in block
        let res = b.points.map{p in [p[0]+move[5], p[1]+h0, p[2]+move[6]]}
        return res
    }

    func neighbors(point:[Int]) -> [[Int]]{ // five directions (no up), no out of bounds
        let x = point[0], y = point[1], z = point[2]
        var res: [[Int]] = []
        let L = state.maxHeight.count
        let W = state.maxHeight[0].count
        for p in [[x-1,y,z],[x+1,y,z],[x,y,z-1],[x,y,z+1],[x,y-1,z]]{
            if p[0] < 0 || p[0] >= L || p[2] < 0 || p[2] >= W { continue }
            if p[1] < 0 || p[1] >= boardStatus[p[0]][p[2]].count { continue }
            res.append(p)
        }
        return res
    }
    
    func isValidMove(points: [[Int]]) -> String{
        var touch = state.history[..<turnNumber].filter{$0[0] != -1}.count == 0
        // If is the first block, no need to check it touches other block of same / different color
        let first = !played(player: currentPlayer)
        let s = state.boardSize
        for p in points{
            // out of bounds
            if p[0]<0 || p[0]>=s[0] || p[2]<0 || p[2] >= s[1] || state.maxHeight[p[0]][p[2]] == 0{
                return "Invalid move: Out of bounds"
            }
            // no overlap
            if boardStatus[p[0]][p[2]].count > p[1]{
                return "Overlap"
            }else{
                // maximum height
                if p[1] >= state.maxHeight[p[0]][p[2]]{
                    return "Invalid move: Maximum height exceeded"
                }
                // no gap
                var i = p[1] - 1
                while i >= boardStatus[p[0]][p[2]].count{
                    if !points.contains([p[0],i,p[2]]){
                        return "Invalid move: There is a gap under"
                    }
                    i -= 1
                }
            }
            if !touch{
                for p0 in neighbors(point: p){
                    let owner = boardStatus[p0[0]][p0[2]][p0[1]]
                    if first || owner == currentPlayer{
                        touch = true
                    }
                }
            }
        }
        if !touch{
            return first ? "Invalid move: Must touch another piece" : "Invalid move: Must touch another piece of yours"
        }else{
            return ""
        }
    }
    
    func getScores() -> [Int]{
        var sc = blocksRemain.map{l in l.map{$0 ? 0 : 1}.reduce(0,+)}
        // one point for each block played
        for row in boardStatus{
            for col in row{
                if col.count > 0{
                    sc[col[col.count-1]] += 1
                }
            }
        }
        return sc
    }
    
    var currentMaxHeight: Int{
        var max = 0
        for row in boardStatus{
            for col in row{
                if col.count > max{
                    max = col.count
                }
            }
        }
        return max
    }
    
    func blockPosYInt(block: Block, xz: [Int]) -> Int{
        // all points may not overlap with existing points
        // h is the smallest Y, return maximum among h
        var h0 = 0
        for p in block.points{
            let x = p[0]+xz[0]
            let z = p[2]+xz[1]
            let s = state.boardSize
            if x>=0 && x<s[0] && z>=0 && z<s[1]{ // If in bound
                let h = boardStatus[x][z].count - p[1]
                if h > h0 {h0 = h}
            }
        }
        return h0
    }
}
