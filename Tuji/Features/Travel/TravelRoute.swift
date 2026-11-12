// Where 跟著 Moira 去旅遊 pushes to. Its own route type, for the reason
// `WordListRoute` gives: the tab stacks hold a `NavigationPath`, and the shared
// destination switch is at its complexity ceiling.

import SwiftUI

enum TravelRoute: Hashable {
    case destination(id: String)
    case city(id: String, destination: String)
    case spot(id: String)
    case study(spotId: String, mode: StudyMode)
}

extension View {
    func travelDestinations() -> some View {
        self.navigationDestination(for: TravelRoute.self) { route in
            switch route {
            case let .destination(id):
                TravelDestinationView(destinationId: id)
            case let .city(id, destination):
                TravelCityView(cityId: id, destinationId: destination)
            case let .spot(id):
                TravelSpotView(spotId: id)
            // No 再來一輪, as for a 個人詞表: the follow-up CTA counts every
            // word due, not this spot's.
            case let .study(spotId, mode):
                StudyLauncherView(
                    mode: mode,
                    queues: SpotStudyQueue(spotId: spotId),
                    allowsAnotherRound: false
                )
            }
        }
    }
}
