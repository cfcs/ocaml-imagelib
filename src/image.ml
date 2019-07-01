(*
 * This file is part of Imagelib.
 *
 * Imagelib is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Imabelib is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Imabelib.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Copyright (C) 2014 Rodolphe Lepigre.
 *)

open ImageUtil

module Pixmap =
  struct
    open Bigarray

    type pixmap8  = (int, int8_unsigned_elt , c_layout) Array2.t
    type pixmap16 = (int, int16_unsigned_elt, c_layout) Array2.t

    type t =
      | Pix8  of pixmap8
      | Pix16 of pixmap16

    let create8  : int -> int -> t = fun w h ->
      Pix8 (Array2.create int8_unsigned c_layout w h)

    let create16 : int -> int -> t = fun w h ->
      Pix16 (Array2.create int16_unsigned c_layout w h)

    let get : t -> int -> int -> int = function
      | Pix8  p -> Array2.get p
      | Pix16 p -> Array2.get p

    let set : t -> int -> int -> int -> unit = function
      | Pix8  p -> Array2.set p
      | Pix16 p -> Array2.set p

    let fill t color : unit = match t with
      | Pix8 p -> Array2.fill p color
      | Pix16 p -> Array2.fill p color

    let copy = function
      | Pix8 p ->
        let w,h = Array2.dim1 p, Array2.dim2 p in
        let fresh = Array2.create int8_unsigned c_layout w h in
        Array2.blit p fresh ; Pix8 fresh
      | Pix16 p ->
        let w,h = Array2.dim1 p, Array2.dim2 p in
        let fresh = Array2.create int16_unsigned c_layout w h in
        Array2.blit p fresh ; Pix16 fresh
  end

type pixmap =
  | Grey  of Pixmap.t
  | GreyA of Pixmap.t * Pixmap.t
  | RGB   of Pixmap.t * Pixmap.t * Pixmap.t
  | RGBA  of Pixmap.t * Pixmap.t * Pixmap.t * Pixmap.t

type image =
  { width   : int
  ; height  : int
  ; max_val : int
  ; pixels  : pixmap }

module type ReadImage =
  sig
    val extensions : string list
    val size       : chunk_reader -> int * int
    val parsefile  : chunk_reader -> image
  end

module type ReadImageStreaming =
  sig
    include ReadImage
    type read_state
    val read_streaming : chunk_reader -> read_state option ->
      image option * int * read_state option
  end

module type WriteImage =
  sig
    val write : chunk_writer -> image -> unit
  end


exception Corrupted_image of string
exception Not_yet_implemented of string

let create_rgb ?(alpha=false) ?(max_val=255) width height =
  if not (1 <= max_val && max_val <= 65535) then
    raise (Invalid_argument
             "create_rgb: false: (1 <= max_val && max_val <= 65535)") ;
  if not (width > 0 && height > 0) then
    raise (Invalid_argument "create_rgb: width or height <= 0") ;
  let create = if max_val <= 255 then Pixmap.create8 else Pixmap.create16 in
  let pixels =
    let r = create width height in
    let g = create width height in
    let b = create width height in
    if alpha then
      let a = create width height in
      RGBA (r,g,b,a)
    else RGB (r,g,b)
  in
  { width ; height ; max_val ; pixels }

let create_grey ?(alpha=false) ?(max_val=255) width height =
  if not (1 <= max_val && max_val <= 65535) then
    raise (Invalid_argument
             "create_grey: false: (1 <= max_val && max_val <= 65535)") ;
  if not (width > 0 && height > 0) then
    raise (Invalid_argument "create_grey: width or height <= 0") ;
  let create = if max_val <= 255 then Pixmap.create8 else Pixmap.create16 in
  let pixels =
    let g = create width height in
    if alpha then
      let a = create width height in
      GreyA (g,a)
    else Grey g
  in
  { width ; height ; max_val ; pixels }

let read_rgba i x y fn =
  match i.pixels with
  | RGB(r,g,b)    ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      let a = i.max_val in
      fn r g b a
  | RGBA(r,g,b,a) ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      let a = Pixmap.get a x y in
      fn r g b a
  | Grey(g)       ->
      let gr = Pixmap.get g x y in
      let a = i.max_val in
      fn gr gr gr a
  | GreyA(g,a)    ->
      let gr = Pixmap.get g x y in
      let a = Pixmap.get a x y in
      fn gr gr gr a

let read_rgb i x y fn =
  match i.pixels with
  | RGB(r,g,b)
  | RGBA(r,g,b,_) ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      fn r g b
  | Grey(g)
  | GreyA(g,_)    ->
      let gr = Pixmap.get g x y in
      fn gr gr gr

let read_greya i x y fn =
  match i.pixels with
  | RGB(r,g,b)    ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      let g = (r + g + b) / 3 in
      let a = i.max_val in
      fn g a
  | RGBA(r,g,b,a) ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      let g = (r + g + b) / 3 in
      let a = Pixmap.get a x y in
      fn g a
  | Grey(g)       ->
      let g = Pixmap.get g x y in
      let a = i.max_val in
      fn g a
  | GreyA(g,a)    ->
      let g = Pixmap.get g x y in
      let a = Pixmap.get a x y in
      fn g a

let read_grey i x y fn =
  match i.pixels with
  | RGB(r,g,b)
  | RGBA(r,g,b,_) ->
      let r = Pixmap.get r x y in
      let g = Pixmap.get g x y in
      let b = Pixmap.get b x y in
      let g = (r + g + b) / 3 in
      fn g
  | Grey(g)
  | GreyA(g,_)    ->
      let g = Pixmap.get g x y in
      fn g

let write_rgba i x y r g b a =
  match i.pixels with
  | RGB(rr,gg,bb)     ->
      begin
        Pixmap.set rr x y r;
        Pixmap.set gg x y g;
        Pixmap.set bb x y b
      end
  | RGBA(rr,gg,bb,aa) ->
      begin
        Pixmap.set rr x y r;
        Pixmap.set gg x y g;
        Pixmap.set bb x y b;
        Pixmap.set aa x y a
      end
  | Grey(gg)          ->
      begin
        let g = (r + g + b) / 3 in
        Pixmap.set gg x y g
      end
  | GreyA(gg,aa)      ->
      begin
        let g = (r + g + b) / 3 in
        Pixmap.set gg x y g;
        Pixmap.set aa x y a
      end

let write_rgb i x y r g b =
  match i.pixels with
  | RGB(rr,gg,bb)
  | RGBA(rr,gg,bb,_) ->
      begin
        Pixmap.set rr x y r;
        Pixmap.set gg x y g;
        Pixmap.set bb x y b
      end
  | Grey(gg)
  | GreyA(gg,_)      ->
      begin
        let g = (r + g + b) / 3 in
        (* TODO see ImageUtil on blending *)
        Pixmap.set gg x y g
      end

let write_greya i x y g a =
  match i.pixels with
  | RGB(rr,gg,bb)     ->
      begin
        Pixmap.set rr x y g;
        Pixmap.set gg x y g;
        Pixmap.set bb x y g
      end
  | RGBA(rr,gg,bb,aa) ->
      begin
        Pixmap.set rr x y g;
        Pixmap.set gg x y g;
        Pixmap.set bb x y g;
        Pixmap.set aa x y a
      end
  | Grey(gg)          ->
      begin
        Pixmap.set gg x y g
      end
  | GreyA(gg,aa)      ->
      begin
        Pixmap.set gg x y g;
        Pixmap.set aa x y a
      end

let write_grey i x y g =
  match i.pixels with
  | RGB(rr,gg,bb)
  | RGBA(rr,gg,bb,_) ->
      begin
        Pixmap.set rr x y g;
        Pixmap.set gg x y g;
        Pixmap.set bb x y g
      end
  | Grey(gg)
  | GreyA(gg,_)      ->
      begin
        Pixmap.set gg x y g
      end

let fill_rgb ?alpha i r g b : unit =
  let fill_rgb ~rr ~gg ~bb =
    Pixmap.fill rr r ;
    Pixmap.fill gg g ;
    Pixmap.fill bb b in
  match i.pixels, alpha with
  | RGBA (rr, gg, bb, aa) , _ ->
    fill_rgb ~rr ~gg ~bb ;
    (match alpha with | None -> ()
                      | Some a -> Pixmap.fill aa a)
  | RGB (rr, gg, bb), None -> fill_rgb ~rr ~gg ~bb
  | RGB _, Some _ -> raise (Corrupted_image "fill_rgb with alpha")
  | Grey _, _ -> raise (Not_yet_implemented "fill_rgb for greyscale")
  | GreyA _, _ -> raise (Not_yet_implemented "fill_rgb for greyscale")

let fill_alpha i c = match i.pixels with
  | Grey _ | RGB _ -> ()
  | RGBA (_, _, _, aa)
  | GreyA (_, aa) -> Pixmap.fill aa c

let copy i = let open Pixmap in
  {i with pixels = match i.pixels with
       | Grey ii -> Grey (copy ii)
       | GreyA (ii,aa) -> GreyA (copy ii, copy aa)
       | RGB (rr,gg,bb)-> RGB (copy rr, copy gg, copy bb)
       | RGBA (rr,gg,bb,aa) -> RGBA (copy rr, copy gg, copy bb, copy aa) }
