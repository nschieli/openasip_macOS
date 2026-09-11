/*
    Copyright (c) 2002-2009 Tampere University.

    This file is part of TTA-Based Codesign Environment (TCE).

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    the rights to use, copy, modify, merge, publish, distribute, sublicense,
    and/or sell copies of the Software, and to permit persons to whom the
    Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
    THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
    FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
    DEALINGS IN THE SOFTWARE.
 */
/**
 * @file MDFView.cc
 *
 * Definition of MFDView class.
 *
 * @author Veli-Pekka J��skel�inen 2003 (vjaaskel-no.spam-cs.tut.fi)
 * @note rating: red
 * @note reviewed Jun 23 2004 by ml, jn, jm, vpj
 */

#include <wx/dcps.h>
#include <wx/sizer.h>
#include <string>
#include "MDFView.hh"
#include "tce_config.h"
#include "MDFDocument.hh"
#include "Machine.hh"
#include "SelectTool.hh"
#include "EditPart.hh"
#include "ProDeConstants.hh"
#include "WxConversion.hh"
#include "FileSystem.hh"
#include "MachineCanvas.hh"
#include "ProDeEditPolicyFactory.hh"
#include "MainFrame.hh"
#include "ADFPrintout.hh"

IMPLEMENT_DYNAMIC_CLASS(MDFView, wxView)

using std::vector;
using std::string;
using namespace TTAMachine;


/**
 * The Constructor.
 */
MDFView::MDFView() :
    wxView(),
    canvas_(NULL),
    frame_(NULL) {
}


/**
 * The Destructor.
 */
MDFView::~MDFView() {
}


/**
 * Implements closing behaviour.
 *
 * Closes the associated document.
 *
 * @param deleteWindow If true, deletes the frame associated with the view.
 * @return true if the associated document was succesfully closed.
 */
bool
MDFView::OnClose(bool deleteWindow) {

    if (!GetDocument()->Close()) {
      return false;
    }

    Activate(false);

    if (deleteWindow) {
	delete canvas_;
        canvas_ = NULL;
	delete frame_;
        frame_ = NULL;
    }
    return true;
}


/**
 * Creates a ChildFrame and a Canvas for the document when a new view
 * is created.
 *
 * @param doc Pointer to the document which this view visualizes.
 * @return True if the ChildFrame and the Canvas was succesfully
 *         created.
 */
bool
MDFView::OnCreate(wxDocument* doc, long) {

    if (doc == NULL) {
        return false;
    }

    // create a childframe for the view
    wxDocMDIParentFrame* mainFrame = wxGetApp().mainFrame();
    frame_ = new ChildFrame(doc, this, mainFrame);
    SetFrame(frame_);

    // Which window actually hosts the canvas differs by platform.
    //
    // wxOSX has NO real MDI: wx/osx/mdi.h un-overrides IsTopLevel() back to
    // true for wxMDIChildFrame, so a "child" frame is a separate top-level
    // window and there is no client area for it to sit inside. Showing it
    // gives two windows -- a near-empty parent holding the menu bar and status
    // bar, and a detached document window -- which is not what the editor is
    // meant to look like. So on Darwin the ChildFrame is kept alive but never
    // shown (the doc/view framework still needs it as the view's frame, and
    // ChildFrame::setStatus already writes to the PARENT's status bar), and
    // the canvas is hosted directly in the main frame. One window, menus in
    // the macOS menu bar where they belong, canvas embedded.
    //
    // Everywhere else, MDI is real and the child frame is shown as usual.
    wxWindow* canvasHost = NULL;
#ifdef __WXOSX__
    canvasHost = mainFrame;
#else
    frame_->Show(true);
    canvasHost = frame_;
#endif

    // create a canvas for the hosting frame
    canvas_ = new MachineCanvas(canvasHost, new ProDeEditPolicyFactory(), frame_);
    // create select tool and set it as active tool for the canvas
    SelectTool* selectTool = new SelectTool(frame_, this);
    canvas_->setTool(selectTool);

    // The canvas is constructed with no explicit size, into a frame that has
    // already been Show()n above, and ChildFrame installs no sizer. On GTK the
    // realize/size-allocate cycle happens to resize the frame's single child
    // to fill it, so this was never noticed. wxOSX lays the frame out when it
    // is shown, so a child added afterwards keeps its default size and the
    // canvas is invisible -- the window comes up empty. Give the frame a real
    // sizer instead of relying on the single-child fallback; this is the
    // portable idiom and behaves identically on GTK.
    wxBoxSizer* frameSizer = new wxBoxSizer(wxVERTICAL);
    frameSizer->Add(canvas_, 1, wxEXPAND);
    canvasHost->SetSizer(frameSizer);
    canvasHost->Layout();

    Activate(true);
    return true;
}


/**
 * Updates the model visualization.
 *
 * @param sender View that sent the update request, or NULL if no
 *               single view requested the update (for instance, when
 *               the document is opened).
 * @param hint Unused at the moment but may in future contain
 *             application-specific information for making updating
 *             more efficient.
 */
void
MDFView::OnUpdate(wxView* /* sender */, wxObject* /* hint */) {

    wxDocument* doc = GetDocument();
    assert(doc != NULL);
    MDFDocument* mdfdoc = dynamic_cast<MDFDocument*>(doc);
    assert(mdfdoc != NULL);

    Model* model = mdfdoc->getModel();
    if (model == NULL) {
        // The model is NULL if document opening fails.
        // View is updated even if the document opening fails.
        return;
    }

    Machine* machine = model->getMachine();
    assert(machine != NULL);
    canvas_->setMachine(machine);
}

/**
 * Returns selected component of the view.
 *
 * @return Pointer to the selected EditPart.
 */
EditPart*
MDFView::selection() {
    if (canvas_ != NULL) {
	return canvas_->selection();
    } else {
	return NULL;
    }
}


/**
 * Clears the component selection.
 */
void
MDFView::clearSelection() {
    canvas_->clearSelection();
}


/**
 * Sets the main frame title when the view is activated.
 */
void
MDFView::OnActivateView(
    bool activate, wxView* /* unused */, wxView* /* unused */) {
    
    if (!activate) {
	wxString title = ProDeConstants::EDITOR_NAME;
        wxGetApp().mainFrame()->SetTitle(title);
        return;
    }

    OnUpdate(NULL, NULL);

    // Update main frame title.
    OnChangeFilename();
    wxGetApp().mainFrame()->updateUI();
}


/**
 * Updates the main and child frame titles when the filename changes.
 */
void
MDFView::OnChangeFilename() {
    string path = WxConversion::toString(GetDocument()->GetFilename());
    string filename = FileSystem::fileOfPath(path);
    wxString title = ProDeConstants::EDITOR_NAME;
    title.Append(_T(" - "));
    title.Append(WxConversion::toWxString(filename));
    wxGetApp().mainFrame()->SetTitle(title);
    frame_->SetTitle(WxConversion::toWxString(filename));
}


/**
 * Returns pointer to the MachineCanvas of the view.
 *
 * @return MachineCanvas of the view.
 */
MachineCanvas*
MDFView::canvas() const {
    return canvas_;
}


/**
 * Handles paint events of the view.
 *
 * @param dc Device context to draw the machine on.
 */
void
MDFView::OnDraw(wxDC* dc) {
    canvas_->OnDraw(*dc);
}


/**
 * Creates printout of the machine figure.
 *
 * @return Printout object of the machine figure for printing.
 */
wxPrintout*
MDFView::OnCreatePrintout() {
    return new ADFPrintout(*canvas_, GetDocument()->GetFilename());
}
