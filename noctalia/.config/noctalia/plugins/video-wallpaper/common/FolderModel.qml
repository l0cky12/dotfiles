pragma ComponentBehavior: Bound
import Qt.labs.folderlistmodel
import QtQuick

Item {
    id: root
    
    required property string folder
    property list<string> filters: []
    readonly property url _folderUrl: folder === "" ? "" : "file://" + folder

    readonly property bool ready: internal.ready
    readonly property list<string> files: internal.files
    readonly property int count: files.length

    function reload() {
        forceReload();
    }

    function forceReload() {
        internal.ready = false;

        if (root.folder === "") {
            internal.files = [];
            internal.ready = true;
            return;
        }

        folderList.folder = "";
        folderList.folder = root._folderUrl;
    }

    function get(index: int): string {
        return files[index];
    }

    function indexOf(file: string): int {
        return files.indexOf(file);
    }

    onFolderChanged: {
        if (root.folder === "")
            forceReload();
    }

    Component.onCompleted: {
        if (root.folder === "")
            forceReload();
    }

    QtObject {
        id: internal
        property bool ready: false
        property list<string> files: []

        function updateFiles() {
            const paths = [];
            for (let index = 0; index < folderList.count; index++)
                paths.push(folderList.get(index, "filePath"));

            files = paths;
        }
    }

    FolderListModel {
        id: folderList
        folder: root._folderUrl
        nameFilters: root.filters
        showDirs: false
        showDotAndDotDot: false
        showHidden: true

        onStatusChanged: {
            internal.ready = status === FolderListModel.Ready;
            if (internal.ready)
                internal.updateFiles();
        }
    }
}
