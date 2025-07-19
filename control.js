const MainContent = document.querySelector("main");
const Explorer = document.querySelector("#explorer-div")


function SetMainView(referenceName) {
    const req = new XMLHttpRequest();
    req.onload = function() {
        if(this.status !== 200) {
            console.log("There was en error fetching the reference page " + referenceName);
            return;
        }
        MainContent.innerHTML = this.responseText;
    }
    req.open("GET", "reference/" + referenceName);
    req.send();
}



function ParseReferenceSelector(toParse, parentObject, depth) {
    let style = "";
    if(depth) style += "padding-left: " + depth + "em;";
    
    const selector = document.createElement("div");

    if(toParse.Reference) {
        selector.innerHTML = toParse.Reference;

        style += "cursor: pointer;";

        selector.tabIndex = 0;
        selector.addEventListener("mouseup", () => SetMainView(toParse.Reference));
    } 
    if(toParse.Label) selector.innerHTML = toParse.Label;

    if(toParse.Children) {
        const summary = document.createElement("summary");
        summary.innerHTML = selector.innerHTML;
        
        const details = document.createElement("details");
        details.appendChild(summary);
        
        for(const child of toParse.Children) ParseReferenceSelector(child, details, depth??0 + 1);
        
        if(toParse.Reference) {
            details.tabIndex = 0;
            details.addEventListener("toggle", () => SetMainView(toParse.Reference));
        }
        
        details.style = style;
        parentObject.appendChild(details);
    } else {
        selector.style = style;
        parentObject.appendChild(selector);
    }
}



const req = new XMLHttpRequest();
req.onload = function() {
    if(this.status !== 200) {
        console.log("There was en error fetching the reference page structure");
        return;
    }
    const response = JSON.parse(this.responseText);

    for(const refObject of response) ParseReferenceSelector(refObject, Explorer);
};
req.open("GET", "reference.json");
req.send();