//
//  ViewController.swift
//  AirPlayVideoDemo
//
//  Created by Crist, Ryan on 10/4/23.
//

import AVFoundation
import AVKit
import UIKit

class PlayerView: UIView {

    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    @available(iOS 17.0, *)
    var sampleBufferVideoRenderer: AVSampleBufferVideoRenderer {
        return sampleBufferDisplayLayer.sampleBufferRenderer
    }

    var sampleBufferDisplayLayer: AVSampleBufferDisplayLayer {
        return layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        let routePickerView = AVRoutePickerView()
        routePickerView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(routePickerView)

        NSLayoutConstraint.activate([
            routePickerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            routePickerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -100)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

class ViewController: UIViewController {

    static let url = URL(string: "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8")!

    lazy var asset: AVAsset = {
        let url = Bundle.main.url(forResource: "bbb", withExtension: "mp4")!
        print(url)
        return AVAsset(url: url)
    }()
    lazy var assetReader = try! AVAssetReader(asset: asset)
    var audioOutput: AVAssetReaderTrackOutput?
    var videoOutput: AVAssetReaderTrackOutput?
    lazy var playerView = PlayerView()

    var videoRenderer: AVQueuedSampleBufferRendering {
        if #available(iOS 17, *) {
            return playerView.sampleBufferVideoRenderer
        }
        return playerView.sampleBufferDisplayLayer
    }
    lazy var audioRenderer = AVSampleBufferAudioRenderer()
    lazy var synchronizer = AVSampleBufferRenderSynchronizer()

    override func loadView() {
        view = playerView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback,
                                         mode: .default,
                                         policy: .longFormVideo)
            try audioSession.setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }

        synchronizer.addRenderer(videoRenderer)
        synchronizer.addRenderer(audioRenderer)
        synchronizer.rate = 1

        Task { await self.load() }
    }

    private func load() async {
        do {
            guard let videoTrack = (try await asset.loadTracks(withMediaType: .video)).first,
                  let audioTrack = (try await asset.loadTracks(withMediaType: .audio)).first
            else { return }
            videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [String(kCVPixelBufferPixelFormatTypeKey):kCVPixelFormatType_32BGRA])
            audioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: [AVFormatIDKey:kAudioFormatLinearPCM])
            assetReader.add(videoOutput!)
            assetReader.add(audioOutput!)
            await play()
        } catch {
            print("uh oh: \(error)")
        }
    }

    @MainActor
    private func play() async {
        assetReader.startReading()
        let queue = DispatchQueue.global(qos: .userInteractive)
        videoRenderer.requestMediaDataWhenReady(on: queue) { [assetReader, videoRenderer, videoOutput] in
            while videoRenderer.isReadyForMoreMediaData {
                guard assetReader.status == .reading else { return }
                guard let sampleBuffer = videoOutput?.copyNextSampleBuffer() else { break }
                videoRenderer.enqueue(sampleBuffer)
            }
        }
        audioRenderer.requestMediaDataWhenReady(on: queue) { [assetReader, audioRenderer, audioOutput] in
            while audioRenderer.isReadyForMoreMediaData {
                guard assetReader.status == .reading else { return }
                guard let sampleBuffer = audioOutput?.copyNextSampleBuffer() else { break }
                audioRenderer.enqueue(sampleBuffer)
            }
        }
    }
}
