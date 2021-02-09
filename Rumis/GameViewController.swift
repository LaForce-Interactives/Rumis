//
//  GameViewController.swift
//  Rumis
//
//  Created by William Dong on 2021/1/10.
//

import UIKit
import QuartzCore
import SceneKit
import ARKit

let PAD: Bool = UIDevice.current.userInterfaceIdiom == .pad

class GameViewController: UIViewController, UIGestureRecognizerDelegate, ARSCNViewDelegate, ARSessionDelegate {
    
    @IBOutlet var scnView: SCNView!
    @IBOutlet var hintLabel: UILabel!
    @IBOutlet var OKButton: UIBarButtonItem!
    @IBOutlet var PassButton: UIBarButtonItem!
    @IBOutlet var ARSwitch: UISwitch!
    @IBOutlet var ARIcon: UIBarButtonItem!
    
    var game: Game! = nil
    var gameNode = SCNNode()
    
    var wireFrame = SCNNode()
    var camNode = SCNNode()
    var ARCamNode = SCNNode()
    var arrowNode = SCNNode()
    
    class func loadFromStoryboard() -> GameViewController{
        let sb = UIStoryboard(name: "Main", bundle: nil)
        let gvc = sb.instantiateViewController(withIdentifier: "gvc") as! GameViewController
        gvc.modalPresentationStyle = .fullScreen
        gvc.modalTransitionStyle = .coverVertical
        return gvc
    }
    
    var tryARscnView: ARSCNView?{
        return scnView as? ARSCNView
    }
    
    var root: SCNNode{
        if let v = tryARscnView{
            return v.scene.rootNode
        }else{
            return scnView.scene!.rootNode
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let scene = SCNScene()
//        scnView.debugOptions = [.showBoundingBoxes]
        scnView.scene = scene
        scnView.delegate = self
        (scnView as? ARSCNView)?.session.delegate = self
//        scnView.showsStatistics = true
        scnView.backgroundColor = UIColor.systemGray5
        
        // load rotate button from scene asset
        let sc = SCNScene(named: "art.scnassets/arrow.scn")!
        let arrow = sc.rootNode.childNode(withName: "arrow", recursively: false)!
        arrow.castsShadow = false
        arrow.centerPivot()
        arrowNode.addChildNode(arrow)
        let bb = arrow.boundingBox
        let bbs = arrow.scale.x
        let bbox = SCNBox(width: CGFloat((bb.max.x-bb.min.x)*bbs),
                          height: CGFloat((bb.max.y-bb.min.y)*bbs),
                          length: CGFloat((bb.max.z-bb.min.z)*bbs), chamferRadius: 0)
        bbox.firstMaterial!.diffuse.contents = UIColor.clear
        arrowNode.geometry = bbox
        arrowNode.castsShadow = false
        makeRotateButtons()
        
        // create and add a camera to the scene
        self.camNode = SCNNode()
        camNode.camera = SCNCamera()
        gameNode.addChildNode(camNode)
        if ARConfiguration.isSupported{
            ARCamNode = scnView.pointOfView!
        }else{
            ARSwitch.isEnabled = false
            ARIcon.isEnabled = false
        }
        scnView.pointOfView = camNode
        
        // create and add a directional light to the scene
        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.castsShadow = true
        lightNode.name = "light"
        lightNode.light!.type = .directional
        lightNode.light!.intensity = 500
        lightNode.eulerAngles = SCNVector3(-Float.pi * 0.49, 0, 0)
        lightNode.position = SCNVector3(x: 0, y: 1, z: 0)
        gameNode.addChildNode(lightNode)
        
        // create and add an ambient light to the scene
        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.lightGray
        scene.rootNode.addChildNode(ambientLightNode)
        
        // Create board and blocks
        gameNode.name = "game root"
        scene.rootNode.addChildNode(gameNode)
        gameNode.addChildNode(createBoard())
        for i in 0..<game.state.playerIDs.count{
            let plate = createPlate(for: i)
            gameNode.addChildNode(plate)
            for bnode in plate.childNodes{
                if !["score", "oltext"].contains(bnode.name!){
                    bnode.move(toParent: gameNode)
                }
            }
        }
        
        // Set original camera position
        let pl = game.isOnline ? GameCenterHelper.helper.currentMatch!.localPlayer : game.currentPlayer
        placeCamera(player: pl, duration: 0)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        FastForwardView()
    }
    
    // MARK: - Configure AR
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Pause the view's session
        tryARscnView?.session.pause()
    }
    
    @IBAction func ToggleAR(_ sender: UISwitch){
        if (sender.isOn){
            let configuration = ARWorldTrackingConfiguration()
            configuration.planeDetection = [.horizontal]
            tryARscnView?.session.run(configuration)
            scnView.pointOfView = ARCamNode
            gameNode.scale = SCNVector3(startARScale, startARScale, startARScale)
            gameNode.animateOpacity(0.0)
            placingAR = true
            hintLabel.text = "Pinch to adjust scale, then tap to place the game"
        }else{
            tryARscnView?.session.pause()
            scnView.pointOfView = camNode
            gameNode.scale = SCNVector3(1.0, 1.0, 1.0)
            gameNode.animateOpacity(1.0)
            placingAR = false
            hintLabel.text = "AR mode is turned off"
        }
    }
    
    // MARK: - ARSessionDelegate
    var placingAR:Bool = false
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if (placingAR){
            var targetOpacity:CGFloat = 0.0
            defer {
                gameNode.animateOpacity(targetOpacity)
            }
            guard let query = tryARscnView?.raycastQuery(from: scnView.center, allowing: .existingPlaneGeometry, alignment: .horizontal) else { return }
            guard let result = tryARscnView?.session.raycast(query).first else {return}
            targetOpacity = 1.0
            let node = SCNNode()
            node.simdTransform = result.worldTransform
            gameNode.position = node.position
            // Setting gameNode positon
            let c = scnView.center
            let p1 = scnView.unprojectPoint(SCNVector3(c.x, c.y, 0))
            let p2 = scnView.unprojectPoint(SCNVector3(c.x, c.y+300, 0))
            let angle = atan2(p2.x-p1.x, p2.z-p1.z)
            gameNode.eulerAngles = SCNVector3(0, .pi+angle, 0)
        }
    }
    
    // MARK: - Game area layout
    // MARK: Block and plate transforms
    let blockPosInPlate: [[Float]] = [
        [2.5,0], [5.5,2.5], [5,0], [8.5,0], [5.5,5],
        [9,2.5], [2.5,2.5], [9,5], [0,2.5], [0,5], [2.5,5]
    ]
    // score at top left
    // 0 2.5 5.5 9 for 2 2 3 3;
    // 2.5 5 8.5 for 2 2 4;
    // 0,2.5,5 on z axis
    let plateCenterOffset: [Float] = [5,2.5] // from [0,0] above to center
    let allPlateCenters: [[Float]] = [
        [0,9], [9,0], [0,-9], [-9,0], [0,18], [0,-18]
    ]
    let allPlateRotYs: [Int] = [0,1,2,3,0,1]
    let plateConfigs: [[Int]] = [[0,2],[0,1,2],[0,1,2,3],[0,1,2,3,4],[0,1,2,3,4,5]] // 2 to 6 players
    var plateCenters: [[Float]] {
        return plateConfigs[game.state.numPlayers-2].map{allPlateCenters[$0]}
    }
    var plateRotYs: [Int] {
        return plateConfigs[game.state.numPlayers-2].map{allPlateRotYs[$0]}
    }
    
    // MARK: Creating the board
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
    
    func createBoard() -> SCNNode{
        let bnode = SCNNode()
        bnode.position = SCNVector3(0, -0.5, 0)
        let boardFrame = SCNPlane(width: 10, height: 10)
        boardFrame.cornerRadius = 1
        boardFrame.firstMaterial!.diffuse.contents = UIColor.gray
        let fnode = SCNNode(geometry: boardFrame)
        fnode.name = "board"
        fnode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
        bnode.addChildNode(fnode)
        // create wireframe
        wireFrame.name = "frame root"
        wireFrame.categoryBitMask = 0b0010
        wireFrame.opacity = 0.0
        bnode.addChildNode(wireFrame)
        let co = game.state.boardCenterOffset
        for x in 0..<game.state.maxHeight.count{
            for z in 0..<game.state.maxHeight[0].count{
                let h = game.state.maxHeight[x][z]
                if h > 0{
                    let grid = SCNPlane(width: 1, height: 1)
                    grid.firstMaterial!.diffuse.contents = UIColor.lightGray
                    let gnode = SCNNode(geometry: grid)
                    gnode.name = "board"
                    gnode.position = SCNVector3(Float(x)-co[0], 0.005, Float(z)-co[1])
                    gnode.eulerAngles = SCNVector3(-Float.pi/2, 0, 0)
                    bnode.addChildNode(gnode)
                    for y in 0...h-1{
                        let snode = SCNNode(geometry: SCNBox(width: 1, height: 1, length: 1, chamferRadius: 0))
                        snode.geometry!.firstMaterial = wireFrameMat
                        snode.name = "frame"
                        snode.categoryBitMask = 0b0010
                        snode.castsShadow = false
                        snode.position = SCNVector3(Float(x)-co[0], Float(y)+0.5, Float(z)-co[1])
                        wireFrame.addChildNode(snode)
                    }
                }
            }
        }
        return bnode
    }
    
    // MARK: Creating block plates with score and oltext
    var origBlockTransforms: [[SCNMatrix4]] = []
    var sceneScoreText: [SCNNode] = []
    var sceneOnlineText: [[SCNNode]] = []
    func createPlate(for player:Int) -> SCNNode{
        let plate = SCNNode()
        plate.name = "plate\(player)"
        let pco = plateCenterOffset
        // Create block nodes
        for i in 0..<11{
            let block = Block(id: i, owner: player)
            let bnode = block.makeShape()
            let pos = blockPosInPlate[i]
            bnode.position = SCNVector3(pos[0]-pco[0], 0, pos[1]-pco[1])
            plate.addChildNode(bnode)
        }
        // Create score text node
        let score = SCNText(string: "0", extrusionDepth: 1)
        score.flatness = 0.1
        let snode = SCNNode(geometry: score)
        snode.centerPivot()
        snode.name = "score"
        snode.position = SCNVector3(-pco[0], 0, -pco[1])
        snode.eulerAngles.x = -.pi/2
        snode.scale = SCNVector3(0.2, 0.2, 0.2)
        plate.addChildNode(snode)
        self.sceneScoreText.append(snode)
        // Create online text node
        // TODO: adjust node positions
        if game.isOnline{
            // Name node
            let nameText = SCNText(string: " ", extrusionDepth: 1)
            nameText.firstMaterial!.diffuse.contents = Game.playerColors[player]
            nameText.flatness = 0.1
            let nameNode = SCNNode(geometry: nameText)
            nameNode.centerPivot()
            nameNode.name = "olname"
            nameNode.position = SCNVector3(0, 0, 4.5)
            nameNode.eulerAngles.x = -.pi/2
            nameNode.scale = SCNVector3(0.1, 0.1, 0.1)
            // Status node
            let statusText = SCNText(string: " ", extrusionDepth: 1)
            statusText.firstMaterial!.diffuse.contents = UIColor.lightGray
            let statusNode = SCNNode(geometry: statusText)
            statusNode.centerPivot()
            statusNode.name = "olstatus"
            statusNode.position = SCNVector3(0, 0, 5.5)
            statusNode.eulerAngles.x = -.pi/2
            statusNode.scale = SCNVector3(0.05, 0.05, 0.05)
            
            plate.addChildNode(nameNode)
            plate.addChildNode(statusNode)
            self.sceneOnlineText.append([nameNode, statusNode])
        }
        // Rotate the whole board
        let ppos = plateCenters[player]
        plate.position = SCNVector3(ppos[0], 0, ppos[1])
        let radY = Float(plateRotYs[player]) * Float.pi / 2
        plate.eulerAngles = SCNVector3(0,radY,0)
        // record original transform (relative to gameNode)
        if origBlockTransforms.count <= player { origBlockTransforms.append([]) }
        for i in 0..<11{
            let name = "\(player)b\(i)"
            let block = plate.childNode(withName: name, recursively: false)!
            origBlockTransforms[player].append(block.worldTransform)
        }
        return plate
    }
    
    // MARK: - Raycasts
    func findTouchedBlock(point: CGPoint) -> SCNNode? {
        if let n = touchedNode(point: point){
            if n.name == nil { return nil }
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
        let hitResults = scnView.hitTest(point, options:[SCNHitTestOption.categoryBitMask : 0b0001])
        if hitResults.count > 0 {
            return hitResults[0].node
        }else{
            return nil
        }
    }
    
    func toggleWireframe(){
        if (wireFrame.opacity == 1.0){
            wireFrame.animateOpacity(0.0)
        }else{
            wireFrame.animateOpacity(1.0)
        }
    }
    
    // MARK: - Selecting / lifting block
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
                sb.position.y = block.centerOffset[1] + Float(game.blockPosYInt(block: block, xz: posint))
            }
            selectedLifted = lifted
            updateRotateButtons()
            SCNTransaction.commit()
        }
    }
    
    var liftedY: Float {
        if let bnode = selectedBlock{
            let y = Block(bnode: bnode).centerOffset[1] + Float(game.currentMaxHeight) + 1
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
            }
        }
        if (putback){
            let block = Block(bnode: sblock)
            sblock.transform = origBlockTransforms[block.owner][block.typeid]
            if (game.currentPlayer != -1){
                hintLabel.text = getTurnHint()
            }
        }
        SCNTransaction.commit()
        selectedBlock = nil
        selectedLifted = false
        updateRotateButtons()
    }
    
    // MARK: - Moving block while aligning with grid
    func getBoardPosInt(bnode: SCNNode) -> [Int]{ // return [] if not in white area
        let block = Block(bnode: bnode)
        let co = block.centerOffset // x, y, z
        let bco = game.state.boardCenterOffset // x, z
        let p = bnode.position
        let intx = Int(round(p.x-co[0]+bco[0]))
        let intz = Int(round(p.z-co[2]+bco[1]))
        return [intx, intz]
    }
    
    func setBoardPosInt(bnode: SCNNode, bpos: [Int]){
        if bpos.count > 0{
            let block = Block(bnode: bnode)
            let co = block.centerOffset // x, y, z
            let bco = game.state.boardCenterOffset // x, z
            let newx = -bco[0] + co[0] + Float(bpos[0])
            let newz = -bco[1] + co[2] + Float(bpos[1])
//            SCNTransaction.begin()
            if abs(newx-bnode.position.x)>0.5 || abs(newz-bnode.position.z)>0.5{
//                SCNTransaction.animationDuration = 0.1
            }
            bnode.position.x = newx
            bnode.position.z = newz
//            SCNTransaction.commit()
        }
    }
    
    func moveBlock(point: CGPoint){
        if let sblock = selectedBlock{
            let wp = scnView.unprojectPoint(SCNVector3(point.x+offsetX, point.y+offsetY, 0.5))
            let p = root.convertPosition(wp, to: gameNode)
            let wcamp = scnView.pointOfView!.worldPosition
            let camp = root.convertPosition(wcamp, to: gameNode)
            let ratio = (liftedY - camp.y) / (p.y - camp.y)
            if (ratio > 0){ // we can move
                var newx = camp.x + ratio * (p.x - camp.x)
                var newz = camp.z + ratio * (p.z - camp.z)
                newx = min(newx, 25)
                newx = max(newx, -25)
                newz = min(newz, 15)
                newz = max(newz, -15)
                sblock.position.x = newx
                sblock.position.z = newz
                if abs(sblock.position.z) <= 5 && abs(sblock.position.x) <= 5{
                    let bpos = getBoardPosInt(bnode: sblock)
                    setBoardPosInt(bnode: sblock, bpos: bpos)
                }
            }
            updateRotateButtons()
        }
    }
    
    func getOnlineHint() -> String{
        if game.isOnline{
            if game.state.history.count > game.turnNumber{
                return "You must Redo to the current move"
            }
            let lp = GameCenterHelper.helper.currentMatch!.localPlayer
            if game.currentPlayer != lp{
                return "It's not the local player (\(Game.playerNames[lp]))'s turn"
            }
        }
        return ""
    }
    
    var pendingMove: [Int] = []
    func releaseBlock(){
        guard let sblock = selectedBlock else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        if abs(sblock.position.x) > 5 || abs(sblock.position.z) > 5{ // out of bounds
            deselectBlock(putback: true)
        }else{
            if (game.currentPlayer != -1){
                let block = Block(bnode:sblock)
                let olhint = getOnlineHint() // Check online validity
                if olhint != ""{
                    hintLabel.text = olhint
                }else{
                    if block.owner == game.currentPlayer{ // Create pending move
                        let bpos = getBoardPosInt(bnode: sblock)
                        setBoardPosInt(bnode: sblock, bpos: bpos)
                        let r = block.rotInts
                        pendingMove = [block.typeid, r[0], r[1], r[2], r[3], bpos[0], bpos[1]]
    //                    print("pending \(pendingMove)")
                        let mes = game.isValidMove(points: game.pointsForMove(move: pendingMove))
                        if (mes == ""){
                            hintLabel.text = "Valid move, tap OK to confirm"
                        }else{
                            hintLabel.text = mes
                        }
                    }else{
                        hintLabel.text = "Invalid move: It is \(Game.playerNames[game.currentPlayer])'s turn"
                    }
                }
            }
            setSelectedLifted(false)
        }
        SCNTransaction.commit()
    }
    
    // MARK: - Handle Gestures
    
    // MARK: Tap to select / lift / rotate
    @IBAction func handleTap(_ gestureRecognize: UIGestureRecognizer) {
        if (placingAR){
            if (gameNode.opacity > 0){
                placingAR = false
                hintLabel.text = "Game placed! You can continue to play."
            }
            return
        }
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
                guard let n = tn.name else { return }
//                print("touched \(n)")
                switch n{
                case "placed point", "frame", "board":
                    toggleWireframe()
                default:
                    if n.prefix(3) == "rot"{
                        ButtonRotate(button: Int(n.suffix(1))!)
                    }
                }
            }
        }
    }
    
    // MARK: Pan to move block / camera / rotate while placing AR
    // TODO: Combine pan and longpress
    var offsetX: CGFloat = 0
    var offsetY: CGFloat = 0
    func setOffset(point: CGPoint){ // projection of origin to touched point
        guard let sblock = selectedBlock else {return}
        var pos = sblock.position
        pos = SCNVector3(pos.x, liftedY, pos.z)
        let wpos = gameNode.convertPosition(pos, to: root)
        let p = scnView.projectPoint(wpos)
        offsetX = CGFloat(p.x) - point.x
        offsetY = CGFloat(p.y) - point.y
    }

    var startEuler: SCNVector3? = nil
    var cameraMoving: Bool = false
    @IBAction func handlePan(_ panGesture: UIPanGestureRecognizer) {
        if placingAR { return }
        let point = panGesture.location(in: scnView)
        switch panGesture.state {
        case .began:
            if findTouchedBlock(point: point) == selectedBlock && selectedBlock != nil{
                setSelectedLifted(true)
                setOffset(point: point)
            }else if !ARSwitch.isOn{
                startEuler = scnView.pointOfView!.eulerAngles
                cameraMoving = true
            }
        case .changed:
            if !cameraMoving{
                self.moveBlock(point: point)
            }else if !ARSwitch.isOn{ // move camera
                let tr = panGesture.translation(in: scnView)
                var radx: Float = startEuler!.x - Float(tr.y) * 0.01
                radx = max(-85 * Float.pi / 180, radx)
                radx = min(-5 * Float.pi / 180, radx)
                var rady: Float = startEuler!.y - Float(tr.x) * 0.01
                rady = rady - floor(rady / (2*Float.pi)) * 2*Float.pi
                scnView.pointOfView!.eulerAngles = SCNVector3(radx, rady, 0)
                let posx = camDistance * cos(-radx) * sin(rady)
                let posy = camDistance * sin(-radx)
                let posz = camDistance * cos(-radx) * cos(rady)
                scnView.pointOfView!.position = SCNVector3(posx, posy, posz)
            }
        case .ended, .cancelled:
            if !cameraMoving{
                releaseBlock()
            }else{
                cameraMoving = false
            }
        default:
            break
        }
    }
    
    // MARK: Long press to select and move block
    var lpSelected = false
    @IBAction func handleLongPress(_ gesture: UILongPressGestureRecognizer){
        if placingAR { return }
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
    
    // MARK: Pinch to scale gameNode or zoom FOV
    var startFOV: CGFloat = 40
    var startARScale: Float = 0.02
    
    @IBAction func handlePinch(_ pinchGesture: UIPinchGestureRecognizer){
        if ARSwitch.isOn && !placingAR { return }
        switch pinchGesture.state{
        case .began:
            if (placingAR){
                startARScale = gameNode.scale.x
                break
            }
            startFOV = scnView.pointOfView!.camera!.fieldOfView
        case .changed:
            if (placingAR){
                var ARScale = startARScale * Float(pinchGesture.scale)
                ARScale = max(ARScale, 0.005)
                ARScale = min(ARScale, 0.05)
                gameNode.scale = SCNVector3(ARScale, ARScale, ARScale)
                break
            }
            var FOV = startFOV / pinchGesture.scale
            FOV = max(FOV, 1)
            FOV = min(FOV, 120)
            scnView.pointOfView!.camera!.fieldOfView = FOV
//        case .ended, .cancelled:
//            if (placingAR){
//                print("ARScale:\(gameNode.scale.x)")
//            }
        default:
            break
        }
    }
    
    // MARK: - Rotate Block
    // six buttons are x+, x-, y+, y-, z+, z-
    var rotateButtons:[SCNNode] = []
    let buttonEulers: [[Float]] = [[0,.pi/2,0],[0,.pi/2*3,0],[-.pi/2,0,0],[.pi/2,0,0],[0,0,0],[0,-.pi,0]]
    let buttonPositions: [[Float]] = [[3,0,0],[-3,0,0],[0,2.5,-1.5],[0,2.5,1.5],[0,0,3],[0,0,-3]]
    
    func makeRotateButtons(){ // and add them to scene
        if rotateButtons.count > 0 { return }
        for i in 0...5{
            let n = arrowNode.clone()
            n.eulerAngles = SCNVector3(floats: buttonEulers[i])
            n.name = "rot\(i)"
            n.animateOpacity(0.0, duration: 0.0)
            rotateButtons.append(n)
            gameNode.addChildNode(n)
        }
    }
    
    func updateRotateButtons(){ // always follow the selected block
        if let sblock = selectedBlock{
            let p = sblock.position
            for i in 0...5{
                let n = rotateButtons[i]
                let v = buttonPositions[i]
                n.position = SCNVector3(p.x+v[0],p.y+v[1],p.z+v[2])
                n.animateOpacity(0.5)
            }
        }else{
            for i in 0...5{
                rotateButtons[i].animateOpacity(0.0)
            }
        }
    }
    
    let buttonAxes: [[Float]] = [[1,0,0],[-1,0,0],[0,1,0],[0,-1,0],[0,0,1],[0,0,-1]]
    func ButtonRotate(button i: Int){
        let axis = buttonAxes[i]
        rotateButtons[i].animateOpacity(1.0, duration: 0.2, back: true)
        RotateSelected(x: axis[0], y: axis[1], z: axis[2])
    }
    
    func RotateSelected(x: Float, y: Float, z: Float){ // by 90 degrees
        if let sblock = selectedBlock{
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            let mat = SCNMatrix4MakeRotation(Float.pi * 0.5, x, y, z)
            let r = sblock.rotation
            let p = sblock.position
            sblock.transform = SCNMatrix4Rotate(mat, r.w, r.x, r.y, r.z)
            sblock.position = p
            SCNTransaction.completionBlock = {
                sblock.setRotInts(rot: sblock.getRotInts())
            }
            SCNTransaction.commit()
            setSelectedLifted(true)
        }
    }
    
    @IBAction func Left(){
        RotateSelected(x: 0, y: -1, z: 0)
    }
    
    @IBAction func Right(){
        RotateSelected(x: 0, y: 1, z: 0)
    }
    
    @IBAction func Up(){
        RotateSelected(x: -1, y: 0, z: 0)
    }
    
    @IBAction func Down(){
        RotateSelected(x: 1, y: 0, z: 0)
    }
    
    @IBAction func Counter(){
        RotateSelected(x: 0, y: 0, z: 1)
    }
    
    @IBAction func Clockwise(){
        RotateSelected(x: 0, y: 0, z: -1)
    }
    
    // MARK: - Turn Transition
    func updateScores(){
        guard let game = game else { return }
        let scores = game.getScores()
        let cp = game.currentPlayer
        for i in 0...scores.count-1{
            let snode = sceneScoreText[i]
            let text = snode.geometry as! SCNText
            text.string = String(scores[i])
            snode.centerPivot()
            let color = i == cp ? Game.playerColors[i] :
                game.passed[i] > 0 ? UIColor.gray : UIColor.white
            text.firstMaterial!.diffuse.contents = color
        }
    }
    
    func UpdateOnlineText(){
        if !game.isOnline{
            return
        }
        guard let cm = GameCenterHelper.helper.currentMatch else {
            return
        }
        for i in 0..<game.state.numPlayers{
            var stateText = "" // later "if" has higher priority
            let isLocal = i == GameCenterHelper.helper.currentMatch!.localPlayer
            if i == game.currentPlayer {
                if isLocal{
                    stateText = "Your Turn"
                }else{
                    stateText = "playing"
                }
            }
            if game.passed[i] > 0{
                stateText = "passed"
            }
            switch cm.participants[i].status{
            case .invited:
                stateText = "invited"
            case .declined:
                stateText = "declined"
            case .matching:
                stateText = "matching"
            default:
                break
            }
            let outcomeTexts = ["none", "quit", "won", "lost", "tied",
                                "expired", "first", "second", "third", "fourth"]
            let outcome = cm.participants[i].matchOutcome
            if outcome != .none{
                stateText = outcomeTexts[outcome.rawValue]
            }
            let t0 = sceneOnlineText[i][0]
            let t1 = sceneOnlineText[i][1]
            if let nameText = cm.participants[i].player?.displayName{
                let you = isLocal ? " (You)" : ""
                (t0.geometry as! SCNText).string = nameText + you
                t0.geometry!.firstMaterial!.diffuse.contents = Game.playerColors[i]
                (t1.geometry as! SCNText).string = stateText
            }else{
                (t0.geometry as! SCNText).string = stateText
                t0.geometry!.firstMaterial!.diffuse.contents = UIColor.lightGray
                (t1.geometry as! SCNText).string = " "
            }
            t0.centerPivot()
            t1.centerPivot()
        }
    }
    
    let camDistance:Float = 30
    func placeCamera(player: Int, duration: Float = 0.5){
        // place the camera
        let radX = 45.0 * Float.pi / 180
        let radY = Float(plateRotYs[player]) * Float.pi / 2
        let xz = camDistance*cos(radX)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = CFTimeInterval(duration)
        camNode.position = SCNVector3(x: xz*sin(radY), y: camDistance*sin(radX), z: xz*cos(radY))
        camNode.eulerAngles = SCNVector3(-radX, radY, 0)
        SCNTransaction.commit()
    }
    
    func setOrientation(player:Int){
        let oris:[UIInterfaceOrientation] = [.portrait, .landscapeLeft, .portraitUpsideDown, .landscapeRight]
        let value = oris[plateRotYs[player]].rawValue
        UIDevice.current.setValue(value, forKey: "orientation")
    }
    
    func getTurnHint() -> String{
        var s: String = ""
        let name = Game.playerNames[game.currentPlayer] // FIXME: game ended
        let tn = game.turnNumber
        let ns = game.state.history.count
        if tn < ns{
            s = "Showing step \(tn)/\(ns)"
        }else{
            if game.isOnline{
                if game.currentPlayer == GameCenterHelper.helper.currentMatch!.localPlayer{
                    s = "Your turn! Tap to select a block"
                }else{
                    s = "Waiting for \(name) to play"
                }
            }else{
                s = "\(name)'s turn. Tap to select a block"
            }
        }
        return s
    }
    
    func startTurn(rotateCamera: Bool = false, rotateScreen: Bool = false){
        updateScores() // including passed / current turn status
        if game.isOnline{
            UpdateOnlineText()
        }
        let cp = game.currentPlayer
        if cp == -1{
            PassButton.isEnabled = false
            PassButton.title = "ended"
            var mes = ""
            let scores = game.getScores()
            for i in 0..<scores.count{
                mes = mes + Game.playerNames[i] + ": " + String(scores[i])
                if i < scores.count-1{
                    mes = mes+"\n"
                }
            }
            let alert=UIAlertController(title:"Game ended!", message: mes, preferredStyle: UIAlertController.Style.alert)
            let cancel=UIAlertAction(title: "OK", style: .cancel)
            alert.addAction(cancel)
            present(alert, animated: true, completion: nil)
            hintLabel.text = "Game ended"
        }else{
            if rotateCamera{
                placeCamera(player: cp)
            }
            if rotateScreen{
                setOrientation(player: cp)
            }
            pendingMove = []
            hintLabel.text = getTurnHint()
        }
    }
    
    @IBAction func OK(){
        let pending = selectedBlock != nil && !selectedLifted && pendingMove.count > 0
        let valid = pending && game.isValidMove(points: game.pointsForMove(move: pendingMove)) == ""
        if valid{
            deselectBlock(putback: false)
            game.executeMove(move: pendingMove)
            if game.isOnline{
                startTurn(rotateCamera: false, rotateScreen: false)
            }else{
                startTurn(rotateCamera: true, rotateScreen: false)
            }
        }else{
            let anim = UIViewPropertyAnimator(duration: 0.1, curve: .linear){
                self.hintLabel.alpha = 0.0
            }
            anim.addCompletion{_ in
                let anim1 = UIViewPropertyAnimator(duration: 0.1, curve: .linear){
                    self.hintLabel.alpha = 1.0
                }
                anim1.startAnimation()
            }
            anim.startAnimation()
            releaseBlock()
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
        let olhint = getOnlineHint()
        if olhint != ""{
            hintLabel.text = olhint
            return
        }
        deselectBlock()
        pendingMove = []
        if (game.currentPlayer != -1){
            game.executeMove(move: [-1])
            if game.isOnline{
                startTurn(rotateCamera: false, rotateScreen: false)
            }else{
                startTurn(rotateCamera: true, rotateScreen: false)
            }
        }
    }
    
    // MARK: - Undo and Redo
    @IBAction func Undo(){
        if game.currentPlayer == -1 { return }
        if game.turnNumber <= 0 { return }
        game.revertStep()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        placeBlock(move: game.state.history[game.turnNumber], reverted: true)
        SCNTransaction.commit()
        startTurn(rotateCamera: false, rotateScreen: false)
    }
    
    @IBAction func Redo(){
        if game.currentPlayer == -1 { return }
        if game.turnNumber >= game.state.history.count { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.2
        placeBlock(move: game.state.history[game.turnNumber])
        SCNTransaction.commit()
        game.replayStep()
        startTurn(rotateCamera: false, rotateScreen: false)
    }
    
    func FastForwardView(){ // Update game and scnView based on game state
        let hist = game.state.history
        if game.turnNumber < hist.count{
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.2
            while game.turnNumber < hist.count-1{
                placeBlock(move: hist[game.turnNumber])
                game.replayStep()
            }
            SCNTransaction.completionBlock = {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.2
                self.placeBlock(move: hist[self.game.turnNumber])
                self.game.replayStep()
                SCNTransaction.commit()
                self.startTurn()
            }
            SCNTransaction.commit()
        }else{
            startTurn()
        }
    }
    
    func placeBlock(move: [Int], reverted: Bool = false){
        let id = move[0]
        if id != -1{
            let owner = game.currentPlayer
            let name = "\(owner)b\(id)"
            let bnode = gameNode.childNode(withName: name, recursively: false)!
            if reverted{
                bnode.transform = origBlockTransforms[owner][id]
            }else{
                bnode.setRotInts(rot: [move[1],move[2],move[3],move[4]])
                let block = Block(bnode: bnode)
                let bpos = [move[5],move[6]]
                setBoardPosInt(bnode: bnode, bpos: bpos)
                bnode.position.y = block.centerOffset[1] + Float(game.blockPosYInt(block: block, xz: bpos))
            }
            for p in bnode.childNodes{
                p.name = reverted ? "point" : "placed point"
            }
        }
    }
    
    @IBAction func ShowMenu(){
        dismiss(animated: true)
    }
    
    // MARK: - Device settings
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
}

extension SCNNode {
    func move(toParent parent: SCNNode) {
        let convertedTransform = convertTransform(SCNMatrix4Identity, to: parent)
        removeFromParentNode()
        transform = convertedTransform
        parent.addChildNode(self)
    }
    
    func animateOpacity(_ targetOpacity: CGFloat, duration: Float = 0.2, back:Bool = false){
        if (opacity != targetOpacity){
            let origOpacity = opacity
            if targetOpacity != 0{
                self.isHidden = false
            }
            SCNTransaction.begin()
            SCNTransaction.animationDuration = CFTimeInterval(duration)
            SCNTransaction.completionBlock = {
                self.isHidden = targetOpacity == 0
                if back{
                    self.animateOpacity(origOpacity, duration: duration)
                }
            }
            opacity = targetOpacity
            SCNTransaction.commit()
        }
    }
    
    func centerPivot(){
        let bb = boundingBox
        pivot = SCNMatrix4MakeTranslation((bb.min.x+bb.max.x)/2,
                                          (bb.min.y+bb.max.y)/2,
                                          (bb.min.z+bb.max.z)/2)
    }
}

extension SCNVector3{
    init(floats: [Float]){
        self.init()
        x = floats[0]
        y = floats[1]
        z = floats[2]
    }
}
