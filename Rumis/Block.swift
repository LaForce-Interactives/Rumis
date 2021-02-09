//
//  Block.swift
//  Rumis
//
//  Created by William Dong on 2021/1/10.
//

import Foundation
import SceneKit

class Block{
    var typeid: Int
    var owner: Int
    var rotInts: [Int] = [0,0,0,0] // rotX, rotY, rotZ in int
    var points:[[Int]] // n by 3 array
    
    static let allPoints: [[[Int]]] = [
        [[0,0,0],[1,0,0]], // 0
        [[0,0,0],[1,0,0],[2,0,0]], // 1
        [[0,0,0],[1,0,0],[1,0,1]], // 2 turn
        [[0,0,0],[1,0,0],[2,0,0],[3,0,0]], // 3 I
        [[0,0,0],[1,0,0],[2,0,0],[0,0,1]], // 4 T
        [[0,0,0],[1,0,0],[2,0,0],[1,0,1]], // 5 L
        [[0,0,0],[1,0,0],[0,0,1],[1,0,1]], // 6 O
        [[0,0,0],[1,0,0],[1,0,1],[2,0,1]], // 7 S
        [[0,0,0],[1,0,0],[0,1,0],[0,0,1]], // 8 3d homo
        [[0,0,0],[1,0,0],[0,0,1],[1,1,0]], // 9 3d sym1
        [[0,0,0],[1,0,0],[0,0,1],[0,1,1]] // 10 3d sym2
    ]
    
    init(id: Int, owner:Int = 0){
        self.typeid = id
        self.owner = owner
        points = Block.allPoints[id]
    }
    
    init(bnode: SCNNode){
        let n = bnode.name!
        owner = Int(n.prefix(1)) ?? 0
        typeid = Int(n.suffix(n.count-2)) ?? 0
        points = Block.allPoints[typeid]
        rotInts = bnode.getRotInts()
        setRotatedPoints()
    }
    
    public var size: [Int]{
        return [0,1,2].map{i in points.map{tup in tup[i]}}.map{
            s in s.max()!-s.min()!+1
        }
    }
    
    public var centerOffset: [Float]{ // From (0,0,0) point to center
        let s = self.size
        return s.map{x in Float(x-1)/2}
    }
    
    public func setRotInts(rot: [Int]){
        rotInts = rot
        setRotatedPoints()
    }
    
    public func setRotatedPoints(){
        let node = SCNNode()
        for p in Block.allPoints[typeid]{
            let subnode = SCNNode()
            subnode.position = SCNVector3(p[0], p[1], p[2])
            node.addChildNode(subnode)
        }
        node.setRotInts(rot: rotInts)
        // record position
        var pos:[[Float]] = node.childNodes.map{
            p in [p.worldPosition.x, p.worldPosition.y, p.worldPosition.z]
        }
        // subtract minimum
        pos = pos.map{
            p in [0,1,2].map{
                i in p[i]-pos.map{p in p[i]}.min()!
            }
        }
        // convert to int
        points = pos.map{
            p in [0,1,2].map{
                i in Int(round(p[i]))
            }
        }
    }
    
    func makeMaterial(_ playerID: Int) -> SCNMaterial{
        let mat = SCNMaterial()
        mat.diffuse.contents = Game.playerColors[playerID]
        return mat
    }
    
    public func makeShape() -> SCNNode{
        let node = SCNNode()
        node.name = "\(owner)b\(typeid)"
        let s = self.size
        let bbox = SCNBox(width: CGFloat(s[0]+1), height: CGFloat(s[1]+1), length: CGFloat(s[2]+1), chamferRadius: 0)
        bbox.firstMaterial!.diffuse.contents = UIColor.clear
//        node.geometry = bbox
        let co = self.centerOffset
        for p in Block.allPoints[typeid] { // no centering for now
            let subnode = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0.1))
            subnode.name = "point"
            subnode.position = SCNVector3(Float(p[0])-co[0], Float(p[1])-co[1], Float(p[2])-co[2])
            subnode.geometry!.replaceMaterial(at: 0, with: makeMaterial(owner))
            node.addChildNode(subnode)
        }
        node.setRotInts(rot: rotInts)
        return node
    }
}

extension SCNNode{ // Convert global orientation and integer rotation numbers
    func getRotInts() -> [Int]{ // [x,y,z,w] in angle axis
        var res:[Int] = [rotation.x, rotation.y, rotation.z].map{
            r in r < -0.2 ? -1 : (r > 0.2 ? 1 : 0)
        }
        let split: Int = [1,4,2,3][res.map{abs($0)}.reduce(0,+)] // splits of 2 pi
        var w = Int(round(rotation.w / (Float.pi * 2 / Float(split)))) % split
        w = w >= 0 ? w : w + split
        if w == 0 { return [0,0,0,0] }
        res.append(w)
        return res
    }
    
    func setRotInts(rot: [Int]){
        let r = rot.map{Float($0)}
        let split = [1,4,2,3][rot.prefix(3).map{abs($0)}.reduce(0,+)]
        let rad = Float.pi * 2 / Float(split) * r[3]
        self.rotation = SCNVector4(r[0], r[1], r[2], rad)
    }
}
