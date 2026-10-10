import MapKit
import SwiftUI

struct NativeLocationMap: UIViewRepresentable {
  let items: [LocationMapItem]
  let focusItems: [LocationMapItem]
  let focusRevision: UUID
  let select: ([LocationMapItem]) -> Void

  func makeCoordinator() -> Coordinator { Coordinator(select: select) }

  func makeUIView(context: Context) -> MKMapView {
    let map = MKMapView()
    map.delegate = context.coordinator
    map.preferredConfiguration = MKStandardMapConfiguration(
      elevationStyle: .flat, emphasisStyle: .muted)
    map.pointOfInterestFilter = .excludingAll
    map.showsUserLocation = false
    map.showsCompass = true
    map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "location")
    map.register(
      MKMarkerAnnotationView.self,
      forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
    return map
  }

  func updateUIView(_ map: MKMapView, context: Context) {
    let coordinator = context.coordinator
    coordinator.select = select
    if coordinator.items != items {
      coordinator.items = items
      map.removeAnnotations(map.annotations)
      map.addAnnotations(items.map(LocationAnnotation.init))
    }
    if coordinator.focusRevision != focusRevision {
      coordinator.focusRevision = focusRevision
      if focusItems.isEmpty {
        map.setRegion(
          MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 20, longitude: 0),
            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 300)), animated: false)
      } else {
        let coordinates = focusItems.map {
          CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        if coordinates.allSatisfy({
          $0.latitude == coordinates[0].latitude && $0.longitude == coordinates[0].longitude
        }) {
          map.setRegion(
            MKCoordinateRegion(
              center: coordinates[0],
              span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)), animated: false)
        } else {
          let ids = Set(focusItems.map(\.id))
          let annotations = map.annotations.compactMap { $0 as? LocationAnnotation }.filter {
            ids.contains($0.item.id)
          }
          let rect = annotations.reduce(MKMapRect.null) { result, annotation in
            let point = MKMapPoint(annotation.coordinate)
            return result.union(MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1)))
          }
          map.setVisibleMapRect(
            rect,
            edgePadding: UIEdgeInsets(
              top: MTLayout.Map.edgeTop, left: MTLayout.Map.edgeSide,
              bottom: MTLayout.Map.edgeBottom, right: MTLayout.Map.edgeSide),
            animated: false)
        }
      }
    }
  }

  static func dismantleUIView(_ map: MKMapView, coordinator: Coordinator) {
    map.delegate = nil
  }

  final class Coordinator: NSObject, MKMapViewDelegate {
    var items: [LocationMapItem] = []
    var focusRevision: UUID?
    var select: ([LocationMapItem]) -> Void
    init(select: @escaping ([LocationMapItem]) -> Void) { self.select = select }

    func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
      guard annotation is LocationAnnotation || annotation is MKClusterAnnotation else {
        return nil
      }
      let cluster = annotation as? MKClusterAnnotation
      let identifier =
        cluster == nil ? "location" : MKMapViewDefaultClusterAnnotationViewReuseIdentifier
      let view =
        mapView.dequeueReusableAnnotationView(withIdentifier: identifier, for: annotation)
        as! MKMarkerAnnotationView
      view.markerTintColor = UIColor(MTColor.accent)
      view.glyphTintColor = UIColor(MTColor.accentInk)
      view.clusteringIdentifier = cluster == nil ? "entry-locations" : nil
      view.canShowCallout = false
      view.displayPriority = cluster == nil ? .defaultHigh : .required
      view.glyphImage = cluster == nil ? UIImage(systemName: "book.closed") : nil
      view.glyphText = cluster.map { String($0.memberAnnotations.count) }
      let members = cluster?.memberAnnotations.compactMap { $0 as? LocationAnnotation }
      view.accessibilityLabel =
        members.map { "\($0.count) record locations. Open associated records." } ?? annotation.title
        ?? "Record Location"
      view.accessibilityIdentifier = cluster == nil ? "map-location-marker" : "map-location-cluster"
      return view
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      let annotations: [LocationAnnotation]
      if let cluster = view.annotation as? MKClusterAnnotation {
        annotations = cluster.memberAnnotations.compactMap { $0 as? LocationAnnotation }
      } else if let annotation = view.annotation as? LocationAnnotation {
        annotations = [annotation]
      } else {
        return
      }
      select(annotations.map(\.item))
      if let annotation = view.annotation {
        mapView.deselectAnnotation(annotation, animated: false)
      }
    }
  }
}

final class LocationAnnotation: NSObject, MKAnnotation {
  let item: LocationMapItem
  var coordinate: CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
  }
  var title: String? { item.title }
  init(item: LocationMapItem) { self.item = item }
}
