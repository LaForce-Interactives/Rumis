//
//  GameViewController.swift
//  Rumis
//
//  Created by William Dong on 2021/1/10.
//

import UIKit
import QuartzCore
import SceneKit

class GameViewController: UIViewController, UIGestureRecognizerDelegate {
    
    @IBOutlet var scnView: SCNView!
    @IBOutlet var hintLabel: UILabel!
    @IBOutlet var OKButton: UIBarButtonItem!
    @IBOutlet var PassButton: UIBarButtonItem!

    var sceneScoreText: [SCNText] = []
    var wireFrame: SCNNode?
    var game: Game? = nil
    
    let camDistance:Float = 30
    var camNode:SCNNode? = nil
    
    func placeCamera(player: Int, duration: Float = 0.5){
        guard let n = camNode else { return }
        // place the camera
        let radX = 45.0 * Float.pi / 180
        let radY = Float(plateRotYs[player]) * Float.pi / 2
        let xz = camDistance*cos(radX)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = CFTimeInterval(duration)
        n.position = SCNVector3(x: xz*sin(radY), y: camDistance*sin(radX), z: xz*cos(radY))
        n.eulerAngles = SCNVector3(-radX, radY, 0)
        SCNTransaction.commit()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // create a new scene
//        let scene = SCNScene(named: "art.scnassets/ship.scn")!
        let scene = SCNScene()
        // Add a block
//        let block = Block(id: 0)
//        let bnode = block.makeShape()
//        bnode.name = "block"
//        bnode.position = SCNVector3(x: 0, y: 0, z: 0)
//        scene.rootNode.addChildNode(bnode)
        
        // create and add a camera to the scene
        self.camNode = SCNNode()
        camNode!.name = "camcam"
        camNode!.camera = SCNCamera()
        scene.rootNode.addChildNode(camNode!)
        
        // create and add a directional light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.castsShadow = true
        lightNode.name = "light"
        lightNode.light!.type = .directional
        lightNode.light!.shadowBias = 2.0
        lightNode.light!.intensity = 500
        lightNode.eulerAngles = SCNVector3(-Float.pi * 0.49, 0, 0)
        lightNode.position = SCNVector3(x: 0, y: 20, z: 0)
        scene.rootNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.lightGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        // set the scene to the view
        scnView.scene = scene
        
        // allows the user to manipulate the camera
        scnView.allowsCameraControl = false
        
        // show statistics such as fps and timing information
        scnView.showsStatistics = true
        
        // configure the view
        scnView.backgroundColor = UIColor.systemGray5
        
        // add a tap gesture recognizer
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        scnView.addGestureRecognizer(tapGesture)
        
        // pan gesture
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        scnView.addGestureRecognizer(panGesture)
        
        // pinch gesture
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        scnView.addGestureRecognizer(pinchGesture)
        
        // pinch gesture
        let lpGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        lpGesture.delegate = self
        lpGesture.minimumPressDuration = 0.1
        scnView.addGestureRecognizer(lpGesture)
        
        // Create board and blocks
        let root = scene.rootNode
        root.addChildNode(createBoard())
        for i in 0..<game!.state.playerIDs.count{
            root.addChildNode(createPlate(for: i))
        }
        
        // Start the first turn
        startTurn()
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    
    var selectedBlock: SCNNode? = nil
    var selectedLifted: Bool = false
    func setSelectedLifted(_ lifted: Bool){
        guard let sb = selectedBlock else { return }
        if (selectedLifted != lifted){
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            if (lifted){
                sb.position.y = liftedY
                hintLabel.text = "Use buttons to rotate, press and hold to move"
            }else{
                let posint = getBoardPosInt(bnode: sb)
                let block = Block(bnode: sb)
                sb.position.y = block.centerOffset[1] + Float(game!.blockPosYInt(block: block, xz: posint))
            }
            selectedLifted = lifted
            SCNTransaction.commit()
        }
    }
    
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    var liftedY: Float {
        if let bnode = selectedBlock{
            let y = Block(bnode: bnode).centerOffset[1] + Float(game!.currentMaxHeight) + 1
            return max(y,2.0)
        }else{
            return 2
        }
    }
    
    func selectBlock(bnode: SCNNode){
        if selectedBlock != nil {
            return
        }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        for node in bnode.childNodes{
            node.geometry!.firstMaterial!.emission.contents = UIColor(white: 0.5, alpha: 0.25)
        }
        SCNTransaction.commit()
        selectedBlock = bnode
        setSelectedLifted(true)
    }
    
    func deselectBlock(putback: Bool = true){
        guard let sblock = selectedBlock else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        for node in selectedBlock!.childNodes{
            node.geometry!.firstMaterial!.emission.contents = UIColor.black
            if !putback{
                node.name = "placed point"
            }// TODO: if bounding box added, rename the block node
        }
        if (putback){
            let pco = plateCenterOffset
            let block = Block(bnode: sblock)
            let p = blockPosInPlate[block.typeid]
            sblock.position = SCNVector3(p[0]-pco[0], 0, p[1]-pco[1])
            sblock.orientation = SCNQuaternion(0,0,0,1)
            if (game!.currentPlayer != -1){
                let colors = ["Red", "Green", "Yellow", "Blue"]
                hintLabel.text = "\(colors[game!.currentPlayer])'s turn, tap to select a block"
            }
        }
        SCNTransaction.commit()
        selectedBlock = nil
        selectedLifted = false
    }
    
    func getBoardPosInt(bnode: SCNNode) -> [Int]{ // return [] if not in white area
        let block = Block(bnode: bnode)
        let co = block.centerOffset // x, y, z
        let bco = game!.state.boardCenterOffset // x, z
        let p = bnode.worldPosition
        let intx = Int(round(p.x-co[0]+bco[0]))
        let intz = Int(round(p.z-co[2]+bco[1]))
        return [intx, intz]
    }
    
    func setBoardPosInt(bnode: SCNNode, bpos: [Int]){
        if bpos.count > 0{
            let block = Block(bnode: bnode)
            let co = block.centerOffset // x, y, z
            let bco = game!.state.boardCenterOffset // x, z
            let newx = -bco[0] + co[0] + Float(bpos[0])
            let newz = -bco[1] + co[2] + Float(bpos[1])
            // TODO: handle board translation and scale
            if abs(newx-bnode.worldPosition.x)>0.5 || abs(newz-bnode.worldPosition.z)>0.5{
//                SCNTransaction.animationDuration = 0.1
            }
            bnode.worldPosition.x = newx
            bnode.worldPosition.z = newz
        }
    }
    
    var pendingMove: [Int] = []
    func releaseBlock(){
        guard let sblock = selectedBlock else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        if abs(sblock.worldPosition.x) > 5 || abs(sblock.worldPosition.z) > 5{ // out of bounds
            deselectBlock()
        }else{
            if (game!.currentPlayer != -1){
                let block = Block(bnode:sblock)
                if block.owner == game!.currentPlayer{ // Create pending move
                    let bpos = getBoardPosInt(bnode: sblock)
                    setBoardPosInt(bnode: sblock, bpos: bpos)
                    let r = block.rotInts
                    pendingMove = [block.typeid, r[0], r[1], r[2], r[3], bpos[0], bpos[1]]
                    print("pending \(pendingMove)")
                    let mes = game!.isValidMove(points: game!.pointsForMove(move: pendingMove))
                    if (mes == ""){
                        hintLabel.text = "Valid move, tap OK to confirm"
                    }else{
                        hintLabel.text = mes
                    }
                }else{
                    let colors = ["Red", "Green", "Yellow", "Blue"]
                    hintLabel.text = "Invalid move: It is \(colors[game!.currentPlayer])'s turn"
                }
            }
            setSelectedLifted(false)
        }
        SCNTransaction.commit()
    }
    
    func findTouchedBlock(point: CGPoint) -> SCNNode? {
        let hitResults = scnView.hitTest(point, options: [:])
        // check that we clicked on at least one object
        if hitResults.count > 0 {
            let n = hitResults[0].node
            if n.name == "point"{
                return n.parent
            }else if n.name!.prefix(2).suffix(1) == "b"{
                return n
            }else{
                return nil
            }
        }else{
            return nil
        }
    }
    
    func touchedNode(point: CGPoint) -> SCNNode?{
        let hitResults = scnView.hitTest(point, options: [:])
        if hitResults.count > 0 {
            return hitResults[0].node
        }else{
            return nil
        }
    }
    
    func toggleWireframe(){
        if wireFrame!.parent == nil{
            scnView.scene!.rootNode.addChildNode(wireFrame!)
        }else{
            wireFrame!.removeFromParentNode()
        }
    }
        
    @objc
    func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        let p = gestureRecognize.location(in: scnView)
        if let bnode = findTouchedBlock(point: p){
            if bnode == selectedBlock{
                if !selectedLifted{
                    setSelectedLifted(true)
                }else{
                    releaseBlock()
                }
            }else{
                deselectBlock()
                selectBlock(bnode: bnode)
            }
        }else{
            if let tn = touchedNode(point: p){
                print("touched \(tn.name!)")
                switch tn.name{
                case "placed point", "frame", "board":
                    toggleWireframe()
                default:
                    break
                }
            }
        }
    }
    
    // var for camera pan
    var startPoint: CGPoint? = nil
    var startEuler: SCNVector3? = nil
    var cameraMoving: Bool = false
    func setOffset(point: CGPoint){ // projection of origin to touched point
        guard let sblock = selectedBlock else {return}
        var pos = sblock.worldPosition
        pos = SCNVector3(pos.x, liftedY, pos.z)
        let p = scnView.projectPoint(pos)
        offsetX = CGFloat(p.x) - point.x
        offsetY = CGFloat(p.y) - point.y
    }
    func moveBlock(point: CGPoint){
        if let sblock = selectedBlock{
            let wp = scnView.unprojectPoint(SCNVector3(point.x+offsetX, point.y+offsetY, 0.5))
            let camp = scnView.pointOfView!.position
            let ratio = (liftedY - camp.y) / (wp.y - camp.y)
            if (ratio > 0){ // we can move
                var newx = camp.x + ratio * (wp.x - camp.x)
                var newz = camp.z + ratio * (wp.z - camp.z)
                newx = min(newx, 25)
                newx = max(newx, -25)
                newz = min(newz, 15)
                newz = max(newz, -15)
                sblock.worldPosition.x = newx
                sblock.worldPosition.z = newz
                if abs(sblock.worldPosition.z) <= 5 && abs(sblock.worldPosition.x) <= 5{
                    let bpos = getBoardPosInt(bnode: sblock)
                    setBoardPosInt(bnode: sblock, bpos: bpos)
                }
            }
        }
    }

    @objc
    func handlePan(_ panGesture: UIPanGestureRecognizer) {
        let point = panGesture.location(in: scnView)
        switch panGesture.state {
        case .began:
            if findTouchedBlock(point: point) == selectedBlock && selectedBlock != nil{
                setSelectedLifted(true)
                setOffset(point: point)
            }else{
                startPoint = point
                startEuler = scnView.pointOfView!.eulerAngles
                cameraMoving = true
            }
        case .changed:
            if !cameraMoving{
                self.moveBlock(point: point)
            }else{ // move camera
                if let sp = startPoint{
                    let dx = point.x - sp.x
                    let dy = point.y - sp.y
                    var radx: Float = startEuler!.x - Float(dy) * 0.01
                    radx = max(-85 * Float.pi / 180, radx)
                    radx = min(-5 * Float.pi / 180, radx)
                    var rady: Float = startEuler!.y - Float(dx) * 0.01
                    rady = rady - floor(rady / (2*Float.pi)) * 2*Float.pi
                    scnView.pointOfView!.eulerAngles = SCNVector3(radx, rady, 0)
                    let posx = camDistance * cos(-radx) * sin(rady)
                    let posy = camDistance * sin(-radx)
                    let posz = camDistance * cos(-radx) * cos(rady)
                    scnView.pointOfView!.position = SCNVector3(posx, posy, posz)
                }
            }
        case .ended, .cancelled:
            if cameraMoving{
                cameraMoving = false
            }else{
                releaseBlock()
            }
        default:
            break
        }
    }
    
    var lpSelected = false
    @objc
    func handleLongPress(_ gesture: UILongPressGestureRecognizer){
        let point = gesture.location(in: scnView)
        switch gesture.state {
        case .began:
            if let bnode = self.findTouchedBlock(point: point){
                if bnode != selectedBlock{
                    deselectBlock()
                    selectBlock(bnode: bnode)
                }else{
                    setSelectedLifted(true)
                }
                lpSelected = true
                setOffset(point: point)
            }
        case .changed:
            if lpSelected{ // do not move block selected by tap
                moveBlock(point: point)
            }
        case .ended, .cancelled:
            releaseBlock()
            lpSelected = false
        default:
            break
        }
    }
    
    var startFOV: CGFloat = 40
    @objc
    func handlePinch(_ pinchGesture: UIPinchGestureRecognizer){
        switch pinchGesture.state{
        case .began:
            startFOV = scnView.pointOfView!.camera!.fieldOfView
        case .changed:
            var FOV = startFOV / pinchGesture.scale
            FOV = max(FOV, 1)
            FOV = min(FOV, 120)
            scnView.pointOfView!.camera!.fieldOfView = FOV
        default:
            break
        }
    }
    
    func printPoints(ps: [[Int]]){
        for y in 0...1{
            for z in 0...1{
                for x in 0...1{
                    print(ps.contains([x,y,z]) ? "O" : ".",terminator: "")
                }
                print("\n",terminator:"")
            }
            print("--")
        }
    }
    
    func ButtonRotate(x: Float, y: Float, z: Float){ // by 90 degrees
        if let sblock = selectedBlock{
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            let mat = SCNMatrix4MakeRotation(Float.pi * 0.5, x, y, z)
            let r = sblock.rotation
            let p = sblock.position
            sblock.transform = SCNMatrix4Rotate(mat, r.w, r.x, r.y, r.z)
            sblock.position = p
            sblock.setRotInts(rot: sblock.getRotInts())
//            let b = Block(bnode: sblock)
//            if b.typeid == 10 { printPoints(ps: b.points) }
            SCNTransaction.commit()
            setSelectedLifted(true)
        }
    }
    
    @IBAction func Left(){
        ButtonRotate(x: 0, y: -1, z: 0)
    }
    
    @IBAction func Right(){
        ButtonRotate(x: 0, y: 1, z: 0)
    }
    
    @IBAction func Up(){
        ButtonRotate(x: -1, y: 0, z: 0)
    }
    
    @IBAction func Down(){
        ButtonRotate(x: 1, y: 0, z: 0)
    }
    
    @IBAction func Counter(){
        ButtonRotate(x: 0, y: 0, z: 1)
    }
    
    @IBAction func Clockwise(){
        ButtonRotate(x: 0, y: 0, z: -1)
    }
    
    // Turn ends
    func updateScores(){
        guard let game = game else { return }
        let scores = game.getScores()
        for i in 0...scores.count-1{
//            sceneScoreText[i].string = "⤻"
            sceneScoreText[i].string = String(scores[i])
        }
    }
    
    func startTurn(){
        let cp = game!.currentPlayer
        if cp == -1{
            PassButton.isEnabled = false
            PassButton.title = "ended"
            let alert=UIAlertController(title:"Good Game", message: "Yeah!", preferredStyle: UIAlertController.Style.alert)
            let cancel=UIAlertAction(title: "OK", style: .cancel)
            alert.addAction(cancel)
            present(alert, animated: true, completion: nil)
            hintLabel.text = "Game ended"
        }else{
            placeCamera(player: cp)
            for i in 0...sceneScoreText.count-1{
                let color = i == cp ? Block.playerColors[i] : UIColor.white
                sceneScoreText[i].firstMaterial!.diffuse.contents = color
            }
            pendingMove = []
            let colors = ["Red", "Green", "Yellow", "Blue"]
            hintLabel.text = "\(colors[game!.currentPlayer])'s turn, tap to select a block"
        }
    }
    
    @IBAction func OK(){
        let pending = selectedBlock != nil && !selectedLifted && pendingMove.count > 0
        let valid = pending && game!.isValidMove(points: game!.pointsForMove(move: pendingMove)) == ""
        if valid{
            deselectBlock(putback: false)
            game!.executeMove(move: pendingMove)
            updateScores()
            startTurn()
        }else{
            let anim = UIViewPropertyAnimator(duration: 0.1, curve: .linear){
                self.hintLabel.alpha = 0.0
            }
            anim.addCompletion{_ in
                print("start1")
                let anim1 = UIViewPropertyAnimator(duration: 0.1, curve: .linear){
                    self.hintLabel.alpha = 1.0
                }
                anim1.startAnimation()
            }
            anim.startAnimation()
            print("start")
            return
        }
    }
    
    @IBAction func AskPASS(sender:UIBarButtonItem) -> Void{
        if sender.title == "PASS"{
            sender.title = "SURE?"
            Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false){
                t in if sender.title == "SURE?"{
                    sender.title = "PASS"
                }
            }
        }else if sender.title == "SURE?"{
            sender.title = "PASS"
            self.PASS()
        }
    }
    
    func PASS(){
        deselectBlock()
        pendingMove = []
        if (game!.currentPlayer != -1){
            game!.executeMove(move: [-1])
            updateScores()
            startTurn()
        }
    }

    
    // block plates layout
    let blockPosInPlate: [[Float]] = [
        [2.5,0], [5.5,2.5], [5,0], [8.5,0], [5.5,5],
        [9,2.5], [2.5,2.5], [9,5], [0,2.5], [0,5], [2.5,5]
    ]
    // score at top left
    // 0 2.5 5.5 9 for 2 2 3 3;
    // 2.5 5 8.5 for 2 2 4;
    // 0,2.5,5 on z axis
    let plateCenterOffset: [Float] = [5,2.5] // from [0,0] above to center
    let plateCenters: [[Float]] = [
        [0,9], [0,-9], [-9,0], [9,0], [0,18], [0,-18]
    ]
    let plateRotYs: [Int] = [0, 2, 3, 1, 0, 2]
    
    var wireFrameMat: SCNMaterial{
        let mat = SCNMaterial()
        let sm = "float u = _surface.diffuseTexcoord.x; \n" +
            "float v = _surface.diffuseTexcoord.y; \n" +
            "int u100 = int(u * 100); \n" +
            "int v100 = int(v * 100); \n" +
            "if (u100 % 99 == 0 || v100 % 99 == 0) { \n" +
            "  // do nothing \n" +
            "} else { \n" +
            "    discard_fragment(); \n" +
            "} \n"
        mat.emission.contents = UIColor.white
        mat.diffuse.contents = UIColor.white
        mat.shaderModifiers = [SCNShaderModifierEntryPoint.surface: sm]
        mat.isDoubleSided = true
        mat.fillMode = .lines
        return mat
    }
    
    // create objects in game scene
    func createBoard() -> SCNNode{
        let boardFrame = SCNPlane(width: 10, height: 10)
        boardFrame.cornerRadius = 1
        boardFrame.firstMaterial!.diffuse.contents = UIColor.gray
        let fnode = SCNNode(geometry: boardFrame)
        fnode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        fnode.position = SCNVector3(0, -0.5, 0)
        fnode.name = "board"
        // create wireframe
        wireFrame = SCNNode()
        wireFrame!.name = "frame root"
//        scnView.scene!.rootNode.addChildNode(wireFrame!)
        let co = game!.state.boardCenterOffset
        for x in 0..<game!.state.maxHeight.count{
            for z in 0..<game!.state.maxHeight[0].count{
                let h = game!.state.maxHeight[x][z]
                if h > 0{
                    let grid = SCNPlane(width: 1, height: 1)
                    grid.firstMaterial!.diffuse.contents = UIColor.lightGray
                    let gnode = SCNNode(geometry: grid)
                    gnode.name = "board"
                    fnode.addChildNode(gnode)
                    gnode.worldPosition = SCNVector3(Float(x)-co[0], -0.495, Float(z)-co[1])
                    for y in 0...h-1{
                        let snode = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
                        snode.geometry!.firstMaterial = wireFrameMat
                        snode.name = "frame"
                        snode.castsShadow = false
                        snode.position = SCNVector3(Float(x)-co[0], Float(y), Float(z)-co[1])
                        wireFrame!.addChildNode(snode)
                    }
                }
            }
        }
        return fnode
    }
    
    func createPlate(for player:Int) -> SCNNode{
        let plate = SCNNode()
        plate.name = "plate\(player)"
        let pco = plateCenterOffset
        for i in 0..<11{
            let block = Block(id: i, owner: player)
            let bnode = block.makeShape()
            let pos = blockPosInPlate[i]
            bnode.position = SCNVector3(pos[0]-pco[0], 0, pos[1]-pco[1])
            plate.addChildNode(bnode)
        }
        let score = SCNText(string: "0", extrusionDepth: 1.0)
        score.flatness = 0.2
        score.containerFrame = CGRect(x: -8, y: -8, width: 16, height: 16)
        score.alignmentMode = CATextLayerAlignmentMode.center.rawValue
        let snode = SCNNode(geometry: score)
        snode.name = "score"
        snode.position = SCNVector3(-pco[0], 0, -pco[1])
        snode.rotation = SCNVector4(-1, 0, 0, Float.pi/2)
        snode.scale = SCNVector3(0.2, 0.2, 0.2)
        self.sceneScoreText.append(score)
        plate.addChildNode(snode)
        let ppos = plateCenters[player]
        plate.position = SCNVector3(ppos[0], 0, ppos[1])
        let radY = Float(plateRotYs[player]) * Float.pi / 2
        plate.eulerAngles = SCNVector3(0,radY,0)
        return plate
    }
    
    override var shouldAutorotate: Bool {
        return true
    }
    
//    override var prefersStatusBarHidden: Bool {
//        return true
//    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
}
