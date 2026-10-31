/*
 * This file is part of FileViewer.
 * Copyright (C) 2026 FileViewer contributors
 *
 * FileViewer is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3,
 * as published by the Free Software Foundation.
 *
 * FileViewer is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with FileViewer. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-only
 */

#import "FVIconView.h"
#import "FVWindow.h"
#import "FVModel.h"

@implementation FVIconView

- (id)initWithOwner:(FVWindow *)controller
{
  if ((self = [super initWithFrame:NSMakeRect (0, 0, 600, 400)]))
    {
      owner = controller;
      selection = [[NSMutableIndexSet alloc] init];
      rowOffsets = [[NSMutableArray alloc] init];
      tileSize = 112;
      anchor = 0;
      [self setAutoresizingMask:NSViewWidthSizable];
      [self registerForDraggedTypes:[NSArray arrayWithObject:NSFilenamesPboardType]];
      [self reload];
    }
  return self;
}

- (void)dealloc
{
  RELEASE (selection);
  RELEASE (rowOffsets);
  RELEASE (mouseDownPath);
  DEALLOC;
}

- (BOOL)isFlipped
{
  return YES;
}

- (BOOL)acceptsFirstResponder
{
  return YES;
}

- (NSInteger)columns
{
  return MAX (1, (NSInteger)([self bounds].size.width / tileSize));
}

- (NSRect)rectForIndex:(NSUInteger)i
{
  NSInteger cols = [self columns];
  NSUInteger row = i / cols;
  CGFloat top = row < [rowOffsets count] ? [[rowOffsets objectAtIndex:row] doubleValue]
                                       : row * tileSize;
  CGFloat bottom = row + 1 < [rowOffsets count]
                       ? [[rowOffsets objectAtIndex:row + 1] doubleValue] : top + tileSize;
  return NSMakeRect ((i % cols) * tileSize, top, tileSize, bottom - top);
}

- (NSDictionary *)labelAttributesForSelection:(BOOL)selected
{
  NSMutableParagraphStyle *style = AUTORELEASE ([[NSMutableParagraphStyle alloc] init]);
  [style setAlignment:NSCenterTextAlignment];
  [style setLineBreakMode:selected ? NSLineBreakByWordWrapping : NSLineBreakByTruncatingMiddle];
  return [NSDictionary dictionaryWithObjectsAndKeys:
      [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
      selected ? [NSColor selectedControlTextColor] : FVViewerTextColor (),
      NSForegroundColorAttributeName, style, NSParagraphStyleAttributeName, nil];
}

- (void)reload
{
  NSUInteger count = [[owner items] count];
  [selection removeIndexesInRange:NSMakeRange (count, NSUIntegerMax - count)];
  NSScrollView *scroll = [self enclosingScrollView];
  CGFloat width = scroll ? [scroll contentSize].width : [self bounds].size.width;
  NSUInteger cols = MAX (1, (NSUInteger)(width / tileSize));
  [rowOffsets removeAllObjects];
  CGFloat height = 0;
  NSUInteger first;
  NSDictionary *attrs = [self labelAttributesForSelection:YES];
  for (first = 0; first < count; first += cols)
    {
      [rowOffsets addObject:[NSNumber numberWithDouble:height]];
      CGFloat rowHeight = tileSize;
      NSUInteger i;
      for (i = first; i < MIN (first + cols, count); i++)
        if ([selection containsIndex:i])
          {
            NSString *name = [[[owner items] objectAtIndex:i] name];
            NSRect text = [name boundingRectWithSize:NSMakeSize (tileSize - 10, 100000)
                options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                attributes:attrs];
            rowHeight = MAX (rowHeight, tileSize * .48 + 15 + ceil (text.size.height) + 8);
          }
      height += rowHeight;
    }
  [rowOffsets addObject:[NSNumber numberWithDouble:height]];
  height = MAX (scroll ? [scroll contentSize].height : 0, height);
  [self setFrameSize:NSMakeSize (width, height)];
  [self updateFileTooltips];
  [self setNeedsDisplay:YES];
}

- (void)updateFileTooltips
{
  [self removeAllToolTips];
  if (!FVFilenameTooltipsEnabled ())
    return;
  NSUInteger i;
  for (i = 0; i < [[owner items] count]; i++)
    [self addToolTipRect:[self rectForIndex:i] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag
             point:(NSPoint)point userData:(void *)data
{
  NSInteger index = [self indexAtPoint:point];
  if (!FVFilenameTooltipsEnabled () || index < 0)
    return nil;
  return [[[owner items] objectAtIndex:index] name];
}

- (void)resizeWithOldSuperviewSize:(NSSize)size
{
  [super resizeWithOldSuperviewSize:size];
  [self reload];
}

- (void)resizeIcons:(CGFloat)delta
{
  tileSize = MIN (192, MAX (80, tileSize + delta));
  [self reload];
}

- (NSIndexSet *)selection
{
  return selection;
}

- (void)setSelection:(NSIndexSet *)indices
{
  [selection removeAllIndexes];
  [selection addIndexes:indices];
  anchor = focusedIndex = [selection count] ? [selection firstIndex] : 0;
  [self reload];
}

- (void)drawRect:(NSRect)dirty
{
  [FVViewerBackgroundColor () set];
  NSRectFill (dirty);
  NSArray *items = [owner items];
  NSUInteger i;
  for (i = 0; i < [items count]; i++)
    {
      NSRect tile = [self rectForIndex:i];
      if (!NSIntersectsRect (tile, dirty))
        continue;
      BOOL selected = [selection containsIndex:i];
      if (selected)
        {
          [[NSColor selectedControlColor] set];
          NSRectFill (NSInsetRect (tile, 3, 3));
        }
      FVItem *item = [items objectAtIndex:i];
      CGFloat size = tileSize * .48;
      NSImage *image = [owner iconForPath:[item path]];
      NSSize imageSize = [image size];
      CGFloat scale = imageSize.width > 0 && imageSize.height > 0
                          ? MIN (size / imageSize.width, size / imageSize.height) : 1;
      [image drawInRect:NSMakeRect (tile.origin.x + (tileSize - imageSize.width * scale) / 2,
                                    tile.origin.y + 9 + (size - imageSize.height * scale) / 2,
                                    imageSize.width * scale, imageSize.height * scale)
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0
          respectFlipped:YES
                   hints:nil];
      NSDictionary *attrs = [self labelAttributesForSelection:selected];
      [[item name] drawInRect:NSMakeRect (tile.origin.x + 5, tile.origin.y + size + 15,
                                          tileSize - 10, tile.size.height - size - 17)
               withAttributes:attrs];
    }
}

- (NSInteger)indexAtPoint:(NSPoint)p
{
  if (p.x < 0 || p.y < 0 || p.x >= [self columns] * tileSize)
    return -1;
  NSUInteger row = 0;
  while (row + 1 < [rowOffsets count]
         && p.y >= [[rowOffsets objectAtIndex:row + 1] doubleValue])
    row++;
  NSInteger i = row * [self columns] + (NSInteger)(p.x / tileSize);
  if ([rowOffsets count] < 2 || row + 1 >= [rowOffsets count])
    return -1;
  return i >= 0 && i < (NSInteger)[[owner items] count] ? i : -1;
}

- (void)mouseDown:(NSEvent *)event
{
  [[self window] makeFirstResponder:self];
  NSInteger i = [self indexAtPoint:[self convertPoint:[event locationInWindow] fromView:nil]];
  NSPoint point = [event locationInWindow];
  if ([event clickCount] == 2 && mouseDownPath
      && fabs (point.x - mouseDownPoint.x) < 5 && fabs (point.y - mouseDownPoint.y) < 5)
    {
      /* Expanding/collapsing labels can move rows between the two clicks. */
      NSUInteger index;
      i = -1;
      for (index = 0; index < [[owner items] count]; index++)
        if ([[[[owner items] objectAtIndex:index] path] isEqual:mouseDownPath])
          {
            i = index;
            break;
          }
    }
  else
    {
      RELEASE (mouseDownPath);
      mouseDownPath = i >= 0 ? [[[[owner items] objectAtIndex:i] path] copy] : nil;
    }
  mouseDownPoint = [event locationInWindow];
  dragPending = i >= 0 && [event clickCount] == 1;
  if (i < 0)
    [selection removeAllIndexes];
  else if ([event modifierFlags] & NSShiftKeyMask)
    {
      anchor = MAX (0, MIN (anchor, (NSInteger)[[owner items] count] - 1));
      [selection addIndexesInRange:NSMakeRange (MIN (anchor, i), labs (anchor - i) + 1)];
    }
  else if ([event modifierFlags] & (NSCommandKeyMask | NSControlKeyMask))
    {
      if ([selection containsIndex:i])
        [selection removeIndex:i];
      else
        [selection addIndex:i];
      anchor = i;
    }
  else if (![selection containsIndex:i])
    {
      [selection removeAllIndexes];
      [selection addIndex:i];
      anchor = i;
    }
  if (i >= 0)
    focusedIndex = i;
  [self reload];
  [owner selectionChanged];
  if ([event clickCount] == 2 && i >= 0)
    [owner open:self];
}

- (void)keyDown:(NSEvent *)event
{
  NSString *text = [event charactersIgnoringModifiers];
  if (![text length])
    return;
  unichar c = [text characterAtIndex:0];
  NSInteger next = [selection count] ? focusedIndex : 0;
  if (c == NSRightArrowFunctionKey)
    next++;
  else if (c == NSLeftArrowFunctionKey)
    next--;
  else if (c == NSDownArrowFunctionKey)
    next += [self columns];
  else if (c == NSUpArrowFunctionKey)
    next -= [self columns];
  else if (c == '\r')
    {
      [owner open:self];
      return;
    }
  else
    {
      NSUInteger i;
      for (i = 0; i < [[owner items] count]; i++)
        if ([[[[owner items] objectAtIndex:i] name]
                rangeOfString:text
                      options:NSCaseInsensitiveSearch | NSAnchoredSearch]
                .location
            == 0)
          {
            next = i;
            break;
          }
    }
  if (![[owner items] count])
    return;
  next = MAX (0, MIN (next, (NSInteger)[[owner items] count] - 1));
  [selection removeAllIndexes];
  if ([event modifierFlags] & NSShiftKeyMask)
    {
      anchor = MAX (0, MIN (anchor, (NSInteger)[[owner items] count] - 1));
      [selection addIndexesInRange:NSMakeRange (MIN (anchor, next), labs (anchor - next) + 1)];
    }
  else
    {
      [selection addIndex:next];
      anchor = next;
    }
  focusedIndex = next;
  [self reload];
  [self scrollRectToVisible:[self rectForIndex:next]];
  [self setNeedsDisplay:YES];
  [owner selectionChanged];
}

- (void)selectAll:(id)sender
{
  [selection addIndexesInRange:NSMakeRange (0, [[owner items] count])];
  [self reload];
  [owner selectionChanged];
}

- (void)mouseDragged:(NSEvent *)event
{
  NSPoint point = [event locationInWindow];
  if (!dragPending
      || (fabs (point.x - mouseDownPoint.x) < 5 && fabs (point.y - mouseDownPoint.y) < 5))
    return;
  dragPending = NO;
  NSArray *paths = [owner selectedPaths];
  if (![paths count])
    return;
  NSPasteboard *pb = [NSPasteboard pasteboardWithName:NSDragPboard];
  [pb declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pb setPropertyList:paths forType:NSFilenamesPboardType];
  NSImage *image = AUTORELEASE ([[owner iconForPath:[paths objectAtIndex:0]] copy]);
  [image setScalesWhenResized:YES];
  [image setSize:NSMakeSize (48, 48)];
  [self dragImage:image
               at:[self convertPoint:[event locationInWindow] fromView:nil]
           offset:NSZeroSize
            event:event
       pasteboard:pb
           source:self
        slideBack:YES];
}

- (void)mouseUp:(NSEvent *)event
{
  dragPending = NO;
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
  return NSDragOperationCopy;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
  return [owner allowsFileDrop] ? NSDragOperationCopy : NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
  if (![owner allowsFileDrop])
    return NO;
  NSArray *paths = [[sender draggingPasteboard] propertyListForType:NSFilenamesPboardType];
  NSInteger i = [self indexAtPoint:[self convertPoint:[sender draggingLocation] fromView:nil]];
  NSString *destination = nil;
  if (i >= 0 && [(FVItem *)[[owner items] objectAtIndex:i] directory])
    destination = [[[owner items] objectAtIndex:i] path];
  [owner runOperation:@"copy" paths:paths destination:destination];
  return YES;
}

@end
