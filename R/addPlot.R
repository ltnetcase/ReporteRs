#' @import rvg
#' @import xml2
#' @title Add a plot into a document object
#'
#' @description Add a plot into a document object
#'
#' @param doc document object
#' @param fun plot function. The function will be executed to produce graphics.
#' For \code{grid} or \code{lattice} or \code{ggplot} object, the function
#' should just be \code{print} and an extra argument \code{x} should specify the object
#' to plot. For traditionnal plots, the function should contain plot instructions. See examples.
#' @param vector.graphic logical scalar, if TRUE, vector graphics are
#' produced instead, PNG images if FALSE.
#' @param pointsize the default pointsize of plotted text in pixels, default to 12 pixels.
#' @param ... further arguments passed to or from other methods. See details.
#' @return a document object
#' @details
#' Plot parameters are specified with the \code{...} argument.
#' However, the most convenient usage is to wrap the plot code
#' into a function whose parameters will be specified as '...'.
#'
#' If you want to add ggplot2 or lattice plot, use \code{print} function.
#'
#' \code{vector.graphic}: DrawingML instructions will be produced
#' for \code{docx} and \code{pptx} objects.
#' Don't use vector graphics if document is a docx and MS Word version
#' used to open the document is 2007.
#'
#' @examples
#'
#' is_sunos <- tolower(Sys.info()[["sysname"]]) == "sunos"
#'
#' options( "ReporteRs-fontsize" = 11 )
#'
#' @export
#' @seealso \code{\link{docx}}, \code{\link{pptx}}
addPlot = function(doc, fun, pointsize = 12, vector.graphic = FALSE, ...){

  checkHasSlide(doc)
  UseMethod("addPlot")
}

# addPlot for docx -------

#' @param width plot width in inches (default value is 6).
#' @param height plot height in inches (default value is 6).
#' @param bookmark id of the Word bookmark to replace by the plot. optional.
#'
#' \code{bookmark} is a character vector specifying bookmark id to replace by the plot(s).\cr
#'   	If provided, plot(s) will replace the paragraph that contains the bookmark.\cr
#'   	If not provided, plot(s) will be added at the end of the document.
#'
#' @param par.properties paragraph formatting properties of the paragraph that contains plot(s).
#' An object of class \code{\link{parProperties}}
#' @param editable logical value - if TRUE vector graphics elements (points, text, etc.) are editable.
#' @param bg the initial background colour.
#' @param fontname_serif,fontname_sans,fontname_mono,fontname_symbol font
#' names for font faces. Use fonts available on operating system.
#' @examples
#'
#' if( check_valid_java_version() ){
#' # plot example for docx -----
#' \donttest{
#' doc = docx( )
#' doc = addPlot( doc, fun = function() barplot( 1:6, col = 2:7),
#'   vector.graphic = TRUE, width = 5, height = 7,
#'   par.properties = parProperties(text.align = "center")
#'   )
#' writeDoc( doc, file = "ex_plot.docx" )
#' }
#' }
#'
#' @rdname addPlot
#' @export
addPlot.docx = function(doc, fun,
                        pointsize = getOption("ReporteRs-fontsize"),
                        vector.graphic = FALSE, width = 6, height = 6,
                        fontname_serif = "Times New Roman",
                        fontname_sans = "Calibri",
                        fontname_mono = "Courier New",
                        fontname_symbol = "Symbol",
                        editable = TRUE, bookmark,
                        par.properties = parProperties(text.align = "center", padding = 5),
                        bg = "transparent", ...) {

  plotargs = list(...)

  dirname = tempfile( )
  dir.create( dirname )

  if( !vector.graphic ){

    filename = paste( dirname, "/plot%03d.png" ,sep = "" )
    grDevices::png (filename = filename,
                    width = width, height = height,
                    units = 'in', pointsize = pointsize, bg = bg,
                    res = 300
    )

    fun(...)
    dev.off()

    plotfiles = list.files( dirname , full.names = TRUE )
    if( length( plotfiles ) < 1 )
      stop("unable to produce a plot")

    if( length( plotfiles ) > 1 )
      stop( length( plotfiles ),
            " files have been produced. multiple plot files are not supported")

    if( !missing( bookmark ) )
      doc = addImage( doc, filename = plotfiles,
                      width = width, height = height,
                      bookmark = bookmark,
                      par.properties = par.properties )
    else
      doc = addImage( doc, filename = plotfiles,
                      width = width, height = height,
                      par.properties = par.properties  )
  } else {
    doc_elt_index = .jcall( doc$obj, "I", "getElementIndex") + 1L

    filename = tempfile( fileext = ".dml")
    filename = normalizePath( filename, winslash = "/", mustWork  = FALSE)

    rel_xml <- rJava::.jcall( doc$obj, "S", "getRelationship_xml" )
    rel_ <- rel_df(rel_xml)
    last_rel_id <- max(rel_$int_id)
    uid <- basename(tempfile(pattern = ""))
    raster_dir <- tempdir()
    img_directory <- file.path(raster_dir, uid )

    dml_docx(file = filename,
             width = width, height = height,
             bg = bg,
             id = doc_elt_index,
             pointsize = pointsize,
             fonts = list(sans=fontname_sans,
                          serif = fontname_serif, mono = fontname_mono,
                          symbol = fontname_symbol),
             editable = editable,
             last_rel_id = last_rel_id,
             raster_prefix = img_directory, standalone = TRUE)
    tryCatch(fun(...),
             finally = dev.off()
    )
    if( !file.exists(filename) )
      stop("unable to produce a plot")

    raster_files <- list.files(path = raster_dir, pattern = paste0("^", uid, "(.*)\\.png$"), full.names = TRUE )
    raster_names <- gsub( pattern = "\\.png$", replacement = "", basename(raster_files) )

    dml_doc = read_xml(filename)
    n_g_elts <- length( xml_find_all(dml_doc, "//*[@id]") )

    dims <- as.integer( c( width*72.2 , height*72.2 )* 12700 )
    dml.object <- .jnew( class.DrawingML, filename )
    .jcall( dml.object, "V", "setWidth", as.integer( dims[1] ) )
    .jcall( dml.object, "V", "setHeight", as.integer( dims[2] ) )

    if( length( raster_files ) > 0 ){
      dims <- lapply( raster_files, function(x) {
        .dims <- attr( readPNG(x), "dim" )
        data.frame(width=.dims[2], height = .dims[1])
      }
      )
      dims <- do.call(rbind, dims)

      .jcall( doc$obj, "V", "add_png",
              .jarray(raster_files), .jarray(raster_names),
              .jarray(dims$width / 72), .jarray(dims$height / 72) )
      unlink(raster_files, force = TRUE)
    }

    if( missing( bookmark ) ){
      .jcall( doc$obj, "V", "add", dml.object, .jParProperties(par.properties) )
    } else {
      .jcall( doc$obj, "V", "add", dml.object, .jParProperties(par.properties), bookmark )
    }
    .jcall( doc$obj, "V", "incrementElementIndex", as.integer( n_g_elts + 1 ) )

  }

  doc
}

# addPlot for pptx -------

#' @param offx,offy optional. x and y position of the shape (left top position of the bounding box) in inches. See details.
#' @details
#'
#' When document is a \code{pptx} object, two positioning methods are available.
#'
#' If arguments offx, offy, width, height are missing, position and dimensions
#' will be defined by the width and height of the next available shape of the slide. This
#' dimensions can be defined in the layout of the PowerPoint template used to create
#' the \code{pptx} object.
#'
#' If arguments offx, offy, width, height are provided, they become position and
#' dimensions of the new shape.
#' @examples
#'
#' if( check_valid_java_version() ){
#' # plot example for pptx -----
#' \donttest{
#' doc = pptx( )
#' doc = addSlide( doc, slide.layout = "Title and Content" )
#'
#' doc = addPlot( doc, fun = function() barplot( 1:6, col = 2:7),
#'   vector.graphic = TRUE, width = 5, height = 4 )
#' if( !is_sunos ){
#'   doc = addPlot( doc,
#'     fun = function() barplot( 1:6, col = 2:7),
#'     vector.graphic = FALSE,
#'     offx = 7, offy = 0,
#'     width = 3, height = 2
#'     )
#' }
#'
#' writeDoc( doc, file = "ex_plot.pptx" )
#' }
#' }
#'
#' @rdname addPlot
#' @export
addPlot.pptx = function(doc, fun, pointsize = 11,
                        vector.graphic = TRUE,
                        fontname_serif = "Times New Roman", fontname_sans = "Calibri",
                        fontname_mono = "Courier New", fontname_symbol = "Symbol",
                        editable = TRUE, offx, offy, width, height,
                        bg = "transparent",
                        ... ) {

  off_missing <- ( missing( offx ) || missing( offy ) )
  ext_missing <- ( missing( width ) || missing( height ) )

  if( !off_missing && ext_missing ){
    stop("width and height must be provided if offx and offy are provided")
  }

  free_layout <- FALSE
  if( off_missing && ext_missing ){
    position <- next_shape_pos( doc )
    offx_ <- position$offx
    offy_ <- position$offy
    width_ <- position$width
    height_ <- position$height
  } else if( off_missing && !ext_missing ){
    position <- next_shape_pos( doc )
    offx_ <- position$offx
    offy_ <- position$offy
    width_ <- width
    height_ <- height
  } else {
    offx_ <- offx
    offy_ <- offy
    width_ <- width
    height_ <- height
    free_layout <- TRUE
  }

  slide = doc$current_slide

  dirname = tempfile( )
  dir.create( dirname )

  if (free_layout && vector.graphic) {
    doc <- vector.pptx.graphic(
      doc = doc, fun = fun, pointsize = pointsize,
      fontname_serif = fontname_serif, fontname_sans = fontname_sans,
      fontname_mono = fontname_mono, fontname_symbol = fontname_symbol,
      editable = editable,
      offx_, offy_, width_, height_,
      bg = bg, free_layout = free_layout,
      ...
    )
  } else if (free_layout && !vector.graphic) {
    doc <- raster.pptx.graphic (
      doc = doc, fun = fun, pointsize = pointsize,
      offx = offx_, offy = offy_, width = width_, height = height_,
      bg = bg, free_layout = free_layout,
      ...
    )
  } else if (!free_layout && vector.graphic) {
    doc <- vector.pptx.graphic(
      doc = doc, fun = fun, pointsize = pointsize,
      fontname_serif = fontname_serif, fontname_sans = fontname_sans,
      fontname_mono = fontname_mono, fontname_symbol = fontname_symbol,
      editable = editable,
      offx_, offy_, width_, height_,
      bg = bg, free_layout = free_layout,
      ...
    )
  } else {
    doc <- raster.pptx.graphic (
      doc = doc, fun = fun, pointsize = pointsize,
      offx = offx_, offy = offy_, width = width_, height = height_,
      bg = bg, free_layout = free_layout,
      ...
    )
  }

  doc
}

