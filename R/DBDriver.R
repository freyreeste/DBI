#' DBIDriver class
#'
#' Base class for all DBMS drivers (e.g., RSQLite, MySQL, PostgreSQL).
#' The virtual class `DBIDriver` defines the operations for creating
#' connections and defining data type mappings.  Actual driver classes, for
#' instance `RPgSQL`, `RMySQL`, etc. implement these operations in a
#' DBMS-specific manner.
#'
#' @docType class
#' @name DBIDriver-class
#' @family DBI classes
#' @family DBIDriver generics
#' @export
#' @include DBObject.R
setClass("DBIDriver", contains = c("DBIObject", "VIRTUAL"))

#' Load and unload database drivers
#'
#' `dbDriver` is a helper method used to create an new driver object
#' given the name of a database or the corresponding R package. It works
#' through convention: all DBI-extending packages should provide an exported
#' object with the same name as the package. `dbDriver` just looks for
#' this object in the right places: if you know what database you are connecting
#' to, you should call the function directly.
#'
#' @section Side Effects:
#' The client part of the database communication is
#' initialized (typically dynamically loading C code, etc.) but note that
#' connecting to the database engine itself needs to be done through calls to
#' `dbConnect`.
#'
#' @param drvName character name of the driver to instantiate.
#' @param drv an object that inherits from `DBIDriver` as created by
#'   `dbDriver`.
#' @param ... any other arguments are passed to the driver `drvName`.
#' @return In the case of `dbDriver`, an driver object whose class extends
#'   `DBIDriver`. This object may be used to create connections to the
#'   actual DBMS engine.
#'
#'   In the case of `dbUnloadDriver`, a logical indicating whether the
#'   operation succeeded or not.
#' @import methods
#' @family DBIDriver generics
#' @examples
#' # Create a RSQLite driver with a string
#' d <- dbDriver("SQLite")
#' d
#'
#' # But better, access the object directly
#' RSQLite::SQLite()
#' @export
setGeneric("dbDriver",
  def = function(drvName, ...) standardGeneric("dbDriver"),
  valueClass = "DBIDriver")

#' @rdname hidden_aliases
setMethod("dbDriver", "character",
  definition = function(drvName, ...) {
    findDriver(drvName)(...)
  }
)

#' @rdname hidden_aliases
#' @param object Object to display
#' @export
setMethod("show", "DBIDriver", function(object) {
  tryCatch(
    # to protect drivers that fail to implement the required methods (e.g.,
    # RPostgreSQL)
    show_driver(object),
    error = function(e) NULL)
  invisible(NULL)
})

show_driver <- function(object) {
  cat("<", is(object)[1], ">\n", sep = "")
}

findDriver <- function(drvName) {
  # If it exists in the global environment, use that
  d <- get2(drvName, globalenv())
  if (!is.null(d)) return(d)

  # Otherwise, see if the appropriately named package is available
  if (is_attached(drvName)) {
    d <- get2(drvName, asNamespace(drvName))
    if (!is.null(d)) return(d)
  }

  pkgName <- paste0("R", drvName)
  # First, see if package with name R + drvName is available
  if (is_attached(pkgName)) {
    d <- get2(drvName, asNamespace(pkgName))
    if (!is.null(d)) return(d)
  }

  # Can't find it:
  stop("Couldn't find driver ", drvName, ". Looked in:\n",
    "* global namespace\n",
    "* in package called ", drvName, "\n",
    "* in package called ", pkgName,
    call. = FALSE)
}

get2 <- function(x, env) {
  if (!exists(x, envir = env)) return(NULL)
  get(x, envir = env)
}


is_attached <- function(x) {
  x %in% loadedNamespaces()
}

#' @rdname dbDriver
#' @family DBIDriver generics
#' @export
setGeneric("dbUnloadDriver",
  def = function(drv, ...) standardGeneric("dbUnloadDriver"),
  valueClass = "logical"
)

#' Create a connection to a DBMS
#'
#' Connect to a DBMS going through the appropriate authorization procedure.
#' Some implementations may allow you to have multiple connections open, so you
#' may invoke this function repeatedly assigning its output to different
#' objects. The authorization mechanism is left unspecified, so check the
#' documentation of individual drivers for details.
#'
#' Each driver will define what other arguments are required, e.g.,
#' `"dbname"` for the database name, `"username"`, and
#' `"password"`.
#'
#' @param drv an object that inherits from \code{\linkS4class{DBIDriver}},
#'   or an existing \code{\linkS4class{DBIConnection}}
#'   object (in order to clone an existing connection).
#' @param ... authorization arguments needed by the DBMS instance; these
#'   typically include `user`, `password`, `dbname`, `host`,
#'   `port`, etc.  For details see the appropriate `DBIDriver`.
#' @return An object that extends \code{\linkS4class{DBIConnection}} in a
#'   database-specific manner. For instance `dbConnect(RMySQL::MySQL())` produces
#'   an object of class `MySQLConnection`. This object is used to direct
#'   commands to the database engine.
#' @seealso [dbDisconnect()] to disconnect from a database.
#' @family DBIDriver generics
#' @export
#' @examples
#' # SQLite only needs a path to the database. Other database drivers
#' # will require more details (like username, password, host, port etc)
#' con <- dbConnect(RSQLite::SQLite(), ":memory:")
#' con
#'
#' dbListTables(con)
#'
#' dbDisconnect(con)
setGeneric("dbConnect",
  def = function(drv, ...) standardGeneric("dbConnect"),
  valueClass = "DBIConnection"
)

#' List currently open connections
#'
#' Drivers that implement only a single connections MUST return a list
#' containing a single element. If no connection are open, methods MUST
#' return an empty list.
#'
#' @param drv A object inheriting from \code{\linkS4class{DBIDriver}}
#' @param ... Other arguments passed on to methods.
#' @family DBIDriver generics
#' @export
#' @return a list
setGeneric("dbListConnections",
  def = function(drv, ...) standardGeneric("dbListConnections")
)

#' Determine the SQL data type of an object
#'
#' This is a generic function. The default method determines the SQL type of an
#' R object according to the SQL 92 specification, which may serve as a starting
#' point for driver implementations. The default method also provides a method
#' for data.frame which will return a character vector giving the type for each
#' column in the dataframe.
#'
#' The data types supported by databases are different than the data types in R,
#' but the mapping between the primitve types is straightforward:  Any of the
#' many fixed and varying length character types are mapped to character
#' vectors. Fixed-precision (non-IEEE) numbers are mapped into either numeric or
#' integer vectors.
#'
#' Notice that many DBMS do not follow IEEE arithmetic, so there are potential
#' problems with under/overflows and loss of precision.
#'
#' @inheritParams dbListConnections
#' @param dbObj A object inheriting from \code{\linkS4class{DBIDriver}}
#'   or \code{\linkS4class{DBIConnection}}
#' @param obj An R object whose SQL type we want to determine.
#' @return A character string specifying the SQL data type for `obj`.
#' @family DBIDriver generics
#' @family DBIConnection generics
#' @examples
#' dbDataType(ANSI(), 1:5)
#' dbDataType(ANSI(), 1)
#' dbDataType(ANSI(), TRUE)
#' dbDataType(ANSI(), Sys.Date())
#' dbDataType(ANSI(), Sys.time())
#' dbDataType(ANSI(), Sys.time() - as.POSIXct(Sys.Date()))
#' dbDataType(ANSI(), c("x", "abc"))
#' dbDataType(ANSI(), list(raw(10), raw(20)))
#' dbDataType(ANSI(), I(3))
#'
#' dbDataType(ANSI(), iris)
#'
#' con <- dbConnect(RSQLite::SQLite(), ":memory:")
#'
#' dbDataType(con, 1:5)
#' dbDataType(con, 1)
#' dbDataType(con, TRUE)
#' dbDataType(con, Sys.Date())
#' dbDataType(con, Sys.time())
#' dbDataType(con, Sys.time() - as.POSIXct(Sys.Date()))
#' dbDataType(con, c("x", "abc"))
#' dbDataType(con, list(raw(10), raw(20)))
#' dbDataType(con, I(3))
#'
#' dbDataType(con, iris)
#'
#' dbDisconnect(con)
#' @export
setGeneric("dbDataType",
  def = function(dbObj, obj, ...) standardGeneric("dbDataType"),
  valueClass = "character"
)

#' @rdname hidden_aliases
#' @export
setMethod("dbDataType", "DBIObject", function(dbObj, obj, ...) {
  dbiDataType(obj)
})
