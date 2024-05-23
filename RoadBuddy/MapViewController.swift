import UIKit
import MapKit
import CoreLocation

class MapViewController: UIViewController, CLLocationManagerDelegate, MKMapViewDelegate {

    @IBOutlet weak var textFieldForAdress: UITextField!
    @IBOutlet weak var getDirectionsButton: UIButton!
    @IBOutlet weak var map: MKMapView!
    
    var locationManager = CLLocationManager()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
        
        map.delegate = self
    }

    @IBAction func getDirectionsTapped(_ sender: Any) {
        textFieldForAdress.resignFirstResponder()
        getAdress()
    }
    
    func getAdress() {
        let geoCoder = CLGeocoder()
        geoCoder.geocodeAddressString(textFieldForAdress.text!) { (placemarks, error)
            in
            guard let placemarks = placemarks, let location = placemarks.first?.location
            else {
                print("Konum bulunamadı!")
                return
            }
            print(location)
            self.mapThis(destinationCord: location.coordinate)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print(locations)
    }
    
    func mapThis(destinationCord: CLLocationCoordinate2D){
        let sourceCordinate = (locationManager.location?.coordinate)!
        let sourcePlaceMark = MKPlacemark(coordinate: sourceCordinate)
        let destPlaceMark = MKPlacemark(coordinate: destinationCord)
        let sourceItem = MKMapItem(placemark: sourcePlaceMark)
        let destItem = MKMapItem(placemark: destPlaceMark)
        let destinationRequest = MKDirections.Request()
        destinationRequest.source = sourceItem
        destinationRequest.destination = destItem
        destinationRequest.transportType = .automobile
        destinationRequest.requestsAlternateRoutes = true
        
        let directions = MKDirections(request: destinationRequest)
        directions.calculate { [weak self] (response, error) in
            guard let self = self else { return }
            
            self.removePreviousRoutes()
            
            guard let response = response else {
                if let error = error {
                    print("Bir şeyler yolunda gitmedi...")
                }
                return
            }
            let route = response.routes[0]
            self.map.addOverlay(route.polyline)
            self.map.setVisibleMapRect(route.polyline.boundingMapRect, animated: true)
        }
    }

    func removePreviousRoutes() {
        if !map.overlays.isEmpty {
            map.removeOverlays(map.overlays)
        }
    }
    
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let render = MKPolylineRenderer(overlay: overlay as! MKPolyline)
        render.strokeColor = .systemOrange
        return render
    }
}

