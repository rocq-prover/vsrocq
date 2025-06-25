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
open Host.Types
open Protocol

val update_processed_success : sentence_id -> exec_overview -> Document.document -> exec_overview
val update_processed_error : sentence_id -> exec_overview -> Document.document -> exec_overview

val cut_overview : sentence_id -> exec_overview -> Document.document -> exec_overview
val prepare_overview : exec_overview -> LspWrapper.Range.t list -> exec_overview

val reset_overview : processed_success:sentence_id list -> processed_error:sentence_id list -> todo:sentence_id list -> Document.document -> exec_overview
val shift_overview : exec_overview -> before:RawDocument.t -> after:RawDocument.t -> start:int -> offset:int -> exec_overview

val overview_until_range : exec_overview -> LspWrapper.Range.t -> exec_overview
val print : exec_overview -> unit