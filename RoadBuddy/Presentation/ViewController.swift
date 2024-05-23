import UIKit
import Vision
import CoreMedia
import AVFoundation

class ViewController: UIViewController {

    @IBOutlet weak var videoPreview: UIView!
    @IBOutlet weak var boxesView: DrawingBoundingBoxView!
    @IBOutlet weak var labelsTableView: UITableView!
    
    @IBOutlet weak var inferenceLabel: UILabel!
    @IBOutlet weak var etimeLabel: UILabel!
    @IBOutlet weak var fpsLabel: UILabel!
    
    lazy var objectDectectionModel = { return try? yolov8m() }()
    
    var request: VNCoreMLRequest?
    var visionModel: VNCoreMLModel?
    var isInferencing = false
    
    var videoCapture: VideoCapture!
    let semaphore = DispatchSemaphore(value: 1)
    var lastExecution = Date()
    
    var predictions: [VNRecognizedObjectObservation] = []
    
    private let camera = Camera()
    
    let maf1 = MovingAverageFilter()
    let maf2 = MovingAverageFilter()
    let maf3 = MovingAverageFilter()
    
    let speechSynthesizer = AVSpeechSynthesizer()
    var spokenLabels: Set<String> = Set()
    var resetTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let statusBarHeight = UIApplication.shared.statusBarFrame.size.height
                let statusBarView = UIView(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: statusBarHeight))
        statusBarView.backgroundColor = UIColor.black
        view.addSubview(statusBarView)
        
        setUpModel()
        setUpCamera()
        camera.delegate = self
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.videoCapture.start()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.videoCapture.stop()
    }
    
    func setUpModel() {
        guard let objectDectectionModel = objectDectectionModel else { fatalError("fail to load the model") }
        if let visionModel = try? VNCoreMLModel(for: objectDectectionModel.model) {
            self.visionModel = visionModel
            request = VNCoreMLRequest(model: visionModel, completionHandler: visionRequestDidComplete)
            request?.imageCropAndScaleOption = .scaleFill
        } else {
            fatalError("fail to create vision model")
        }
    }

    func setUpCamera() {
        videoCapture = VideoCapture()
        videoCapture.delegate = self
        videoCapture.fps = 30
        videoCapture.setUp(sessionPreset: .vga640x480) { success in
            
            if success {
                if let previewLayer = self.videoCapture.previewLayer {
                    self.videoPreview.layer.addSublayer(previewLayer)
                    self.resizePreviewLayer()
                }
                
                self.videoCapture.start()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        resizePreviewLayer()
    }
    
    func resizePreviewLayer() {
        videoCapture.previewLayer?.frame = videoPreview.bounds
    }
}

extension ViewController: VideoCaptureDelegate {
    func videoCapture(_ capture: VideoCapture, didCaptureVideoFrame pixelBuffer: CVPixelBuffer?, timestamp: CMTime) {
        if !self.isInferencing, let pixelBuffer = pixelBuffer {
            self.isInferencing = true
            self.camera.startCamera()
            self.predictUsingVision(pixelBuffer: pixelBuffer)
        }
    }
}

extension ViewController {
    func predictUsingVision(pixelBuffer: CVPixelBuffer) {
        guard let request = request else { fatalError() }
        self.semaphore.wait()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
        try? handler.perform([request])
    }
    
        func visionRequestDidComplete(request: VNRequest, error: Error?) {
            self.camera.tagLabel(with: "endInference")

            if let predictions = request.results as? [VNRecognizedObjectObservation] {
                let filteredPredictions = predictions.filter { $0.labels.first?.confidence ?? 0 >= 0.999 }

                self.predictions = filteredPredictions
                DispatchQueue.main.async {
                    self.boxesView.predictedObjects = filteredPredictions
                    self.labelsTableView.reloadData()
                    self.camera.stopCamera()
                    self.isInferencing = false
                    self.speakLabels()
                }
            } else {
                self.camera.stopCamera()
                self.isInferencing = false
            }

            self.semaphore.signal()
        }

    func speakLabels() {
        guard !predictions.isEmpty else {
            return
        }
        
        var labelsToSpeak: [String] = []
        
        for prediction in predictions {
            guard let label = prediction.label, !spokenLabels.contains(label) else {
                continue
            }
            
            labelsToSpeak.append(label)
            spokenLabels.insert(label)
        }
        
        guard !labelsToSpeak.isEmpty else {
            return
        }
        
        let labelsString = labelsToSpeak.joined(separator: ", ")
        let speechUtterance = AVSpeechUtterance(string: labelsString)
        speechSynthesizer.speak(speechUtterance)
        
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            self.spokenLabels.removeAll()
        }
    }

}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return predictions.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "InfoCell") else {
            return UITableViewCell()
        }

        let confidence = predictions[indexPath.row].labels.first?.confidence ?? -1
        let confidencePercentage = Int(confidence * 100)
        cell.textLabel?.text = predictions[indexPath.row].label ?? "N/A"
        cell.detailTextLabel?.text = "Doğruluk Oranı: %\(confidencePercentage)"
        return cell
    }
}

extension ViewController: CameraDelegate {
    func updateMeasure(inferenceTime: Double, executionTime: Double, fps: Int) {
        DispatchQueue.main.async {
            self.maf1.append(element: Int(inferenceTime*1000.0))
            self.maf2.append(element: Int(executionTime*1000.0))
            self.maf3.append(element: fps)
            self.inferenceLabel.text = "inference: \(self.maf1.averageValue) ms"
            self.etimeLabel.text = "execution: \(self.maf2.averageValue) ms"
            self.fpsLabel.text = "fps: \(self.maf3.averageValue)"
        }
    }
}

class MovingAverageFilter {
    private var arr: [Int] = []
    private let maxCount = 10
    
    public func append(element: Int) {
        arr.append(element)
        if arr.count > maxCount {
            arr.removeFirst()
        }
    }
    
    public var averageValue: Int {
        guard !arr.isEmpty else { return 0 }
        let sum = arr.reduce(0) { $0 + $1 }
        return Int(Double(sum) / Double(arr.count))
    }
}
