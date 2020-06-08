//
//  ViewController.swift
//  SSAudioQueuePlayer
//
//  Created by Michael on 2020/4/21.
//  Copyright © 2020 Michael. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    let player = SSAudioQueuePlayer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
    }

    @IBAction func play(_ sender: Any) {
        let filePath = Bundle.main.path(forResource: "平凡之路", ofType: "mp3")!
        
        player.play(url: NSURL.fileURL(withPath: filePath) as NSURL)
    }

}

