(**************************************************************************)
(*                                                                        *)
(*                                 VSRocq                                 *)
(*                                                                        *)
(*                   Copyright INRIA and contributors                     *)
(*       (see version control and README file for authors & dates)        *)
(*                                                                        *)
(**************************************************************************)
(*                                                                        *)
(*   This file is distributed under the terms of the MIT License.         *)
(*   See LICENSE file.                                                    *)
(*                                                                        *)
(**************************************************************************)

val interrupt : doc_id:Types.document_id -> unit

val run :
  doc_id:Types.document_id ->
  (unit -> 'a) ->
  'a Types.interruptible_result Sel.Promise.t

val try_run :
  doc_id:Types.document_id ->
  timeout:float ->
  (unit -> 'a) ->
  ('a,Exninfo.iexn) Result.t
