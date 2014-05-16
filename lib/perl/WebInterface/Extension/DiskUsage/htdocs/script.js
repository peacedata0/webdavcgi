/*********************************************************************
(C) ZE CMS, Humboldt-Universitaet zu Berlin
Written 2014 by Daniel Rohde <d.rohde@cms.hu-berlin.de>
**********************************************************************
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
**********************************************************************/
$(document).ready(function() {
	// handle file actions:
	$("body").on("fileActionEvent", function(event,data) {
		if (data.obj.hasClass("disabled")) return;
		if (data.obj.hasClass("diskusage") && data.obj.hasClass("listaction")) {
			var selrows = $("#fileList tr.selected.is-dir:visible");
			var files = selrows.length>0 ? $.map(selrows, function(val,i) { return $(val).attr("data-file")}) : new Array(!data.file ? '' : data.file);
			du_dialog(files);
		} else if (data.obj.hasClass("diskusage")) {
			du_dialog(new Array(data.file));
		}
	});
	$("#flt").on("fileListChanged", function() {
		var flt = $("#fileListTable");
		$("#apps .listaction.diskusage").toggleClass("disabled", flt.hasClass("unselectable-yes") || flt.hasClass("isreadable-no"));
	});
	function du_dialog(files) {
		$(".action.diskusage").addClass("disabled");
		var block=du_blockPage();
		$.post($("#fileList").attr("data-uri"),{action: "diskusage", file: files}, function (response) {
			var dialog = $(response);
			block.remove();
			var ch = function(event) {
				window.location.href = $("a",$(this)).attr("href");
			};
			$("tr.diskusage.entry", dialog).dblclick(ch).click(ch);
			dialog.dialog({modal: true, width: "auto", height: "auto", maxWidth:"800", resizable: true, 
					open: function() { du_initAccordion(dialog); }, 
					close: function() { dialog.dialog("destroy")}});			
			$(".action.diskusage").removeClass("disabled");
		});
	}
	function du_initAccordion(dialog) {
		$(".accordion",dialog).accordion({collapsible: true, active: false, heightStyle:"content"});
	}
	function du_blockPage() {
		return $("<div></div>").prependTo("body").addClass("overlay");
	}
});