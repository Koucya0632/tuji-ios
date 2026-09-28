// A zero-size view that is always drawn.
//
// SwiftUI does not run `.task` on a view whose body renders nothing. A view that
// hides itself until its own load has answered therefore never loads: the member
// features (詞表 entry, 加入詞表, 我的筆記, 詞條延伸內容) all shipped that way and
// sent no request at all — found only by running the app against a v2 server.
// They cannot draw a skeleton instead, because under membership v1 they must not
// be seen at all. Putting one of these in the container gives `.task` a view.

import SwiftUI

struct TaskAnchor: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
